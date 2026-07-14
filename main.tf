# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Look up the default VPC so we don't create an unnecessary one.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Use the latest Ubuntu 22.04 LTS AMI unless an AMI ID is provided.
data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Look up the Route53 hosted zone when a domain is specified but no zone ID.
data "aws_route53_zone" "primary" {
  count        = var.domain_name != "" && var.route53_zone_id == "" ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  ami_id = coalesce(var.ami_id, try(data.aws_ami.ubuntu[0].id, ""))

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )

  # Pick the first default subnet for the ENI.
  subnet_id = try(tolist(data.aws_subnets.default.ids)[0], "")

  # Whether we have a domain for TLS.
  has_domain = var.domain_name != ""

  # The zone ID — either explicitly provided or looked up.
  zone_id = coalesce(var.route53_zone_id, try(data.aws_route53_zone.primary[0].zone_id, ""))

  # Access URL depends on whether we have TLS.
  access_url = local.has_domain ? "https://${var.domain_name}" : "http://${aws_eip.this.public_ip}"

  # Caddy address line — TLS if domain, plain HTTP otherwise.
  caddy_address = local.has_domain ? var.domain_name : ":80"
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name_prefix = "${var.project_name}-${var.environment}-"
  description = "Security group for private LLM stack (${var.project_name} ${var.environment})"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset([for cidr in var.allowed_cidrs : cidr if cidr != ""])

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from allowed CIDR"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset([for cidr in var.allowed_cidrs : cidr if cidr != ""])

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from allowed CIDR"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset([for cidr in var.allowed_cidrs : cidr if cidr != ""])

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from allowed CIDR"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound traffic"
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  monitoring                  = var.enable_detailed_monitoring

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-root"
    })
  }

  # Additional EBS volume for model storage.
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_type = "gp3"
    volume_size = var.volume_size_gb
    encrypted   = true
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-models"
    })
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    model_name     = var.model_name
    domain_name    = var.domain_name
    admin_username = var.admin_username
    admin_password = var.admin_password
    caddy_address  = local.caddy_address
    volume_size_gb = var.volume_size_gb
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-instance"
  })
}

# -----------------------------------------------------------------------------
# Elastic IP
# -----------------------------------------------------------------------------

resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-eip"
  })

  depends_on = [aws_instance.this]
}

# -----------------------------------------------------------------------------
# Route53 Record (conditional — only when domain_name is provided)
# -----------------------------------------------------------------------------

resource "aws_route53_record" "this" {
  count = local.has_domain ? 1 : 0

  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 60
  records = [aws_eip.this.public_ip]

  depends_on = [aws_eip.this]
}
