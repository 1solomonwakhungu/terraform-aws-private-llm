# =============================================================================
# Complete Example — Private LLM Stack
# =============================================================================
# Deploys a production-grade private LLM endpoint:
#   - GPU instance running Ollama + Open WebUI
#   - Auto-TLS via Caddy with a Route53-managed domain
#   - Network access restricted to a corporate CIDR range
#   - Larger EBS volume for hosting a 70B-parameter model
#   - Detailed monitoring enabled
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "admin_password" {
  description = "Basic-auth password for Open WebUI. Provide via TF_VAR_admin_password or a secrets manager."
  type        = string
  sensitive   = true
}

module "private_llm" {
  source = "../../"

  aws_region    = "us-east-1"
  instance_type = "g5.2xlarge"
  model_name    = "llama3.1:70b"

  # Auto-TLS: Caddy requests a certificate for this domain and Route53
  # publishes the A record pointing at the Elastic IP.
  domain_name     = "llm.example.com"
  route53_zone_id = "Z0123456789ABCDEFGHIJ"

  admin_username = "platform-admin"
  admin_password = var.admin_password

  # Restrict SSH/HTTP/HTTPS to the corporate VPN range.
  allowed_cidrs = ["203.0.113.0/24"]

  # 70B models need ample disk for the weights plus container data.
  volume_size_gb = 300

  project_name = "private-llm"
  environment  = "prod"

  enable_detailed_monitoring = true

  tags = {
    Owner   = "infra-team"
    Billing = "ai-infra"
    Tier    = "gpu-70b"
  }
}

output "access_url" {
  description = "HTTPS URL to reach Open WebUI"
  value       = module.private_llm.access_url
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = module.private_llm.ssh_command
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = module.private_llm.instance_id
}
