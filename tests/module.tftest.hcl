mock_provider "aws" {}

override_data {
  target = data.aws_vpc.default

  values = {
    id = "vpc-0123456789abcdef0"
  }
}

override_data {
  target = data.aws_subnets.default

  values = {
    ids = [
      "subnet-0123456789abcdef0",
      "subnet-0123456789abcdef1",
    ]
  }
}

override_resource {
  target          = aws_eip.this
  override_during = plan

  values = {
    id        = "eipalloc-0123456789abcdef0"
    public_ip = "198.51.100.10"
  }
}

run "plans_http_deployment" {
  command = plan

  variables {
    admin_password = "correct-horse-battery-staple"
    ami_id         = "ami-0123456789abcdef0"
    instance_type  = "t3.medium"
    allowed_cidrs  = ["198.51.100.0/24", "203.0.113.0/24"]
    volume_size_gb = 200
    project_name   = "per237"
    environment    = "test"

    tags = {
      Owner = "platform"
    }
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0123456789abcdef0"
    error_message = "The configured AMI must be passed to the instance."
  }

  assert {
    condition     = aws_instance.this.subnet_id == "subnet-0123456789abcdef0"
    error_message = "The instance must use a subnet from the default VPC."
  }

  assert {
    condition     = one(aws_instance.this.root_block_device).encrypted
    error_message = "The root volume must be encrypted."
  }

  assert {
    condition     = one(aws_instance.this.ebs_block_device).encrypted && one(aws_instance.this.ebs_block_device).volume_size == 200
    error_message = "Model storage must be encrypted and use the requested size."
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.ssh) == 2 &&
      length(aws_vpc_security_group_ingress_rule.http) == 2 &&
      length(aws_vpc_security_group_ingress_rule.https) == 2
    )
    error_message = "Each allowed CIDR must receive SSH, HTTP, and HTTPS rules."
  }

  assert {
    condition     = length(aws_route53_record.this) == 0
    error_message = "No Route53 record should be created without a domain."
  }

  assert {
    condition     = output.access_url == "http://198.51.100.10"
    error_message = "HTTP deployments must expose the Elastic IP URL."
  }

  assert {
    condition     = aws_instance.this.tags["Owner"] == "platform"
    error_message = "Caller-supplied tags must be propagated."
  }
}

run "plans_domain_and_dns" {
  command = plan

  variables {
    admin_password  = "correct-horse-battery-staple"
    ami_id          = "ami-0123456789abcdef0"
    domain_name     = "llm.example.com"
    route53_zone_id = "Z0123456789ABCDEF"
    allowed_cidrs   = ["203.0.113.0/24"]
  }

  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "A domain must create one Route53 A record."
  }

  assert {
    condition = (
      aws_route53_record.this[0].zone_id == "Z0123456789ABCDEF" &&
      aws_route53_record.this[0].name == "llm.example.com" &&
      toset(aws_route53_record.this[0].records) == toset(["198.51.100.10"])
    )
    error_message = "The Route53 record must point the configured domain to the Elastic IP."
  }

  assert {
    condition     = output.access_url == "https://llm.example.com"
    error_message = "Domain deployments must expose an HTTPS URL."
  }
}

run "rejects_unsupported_instance_family" {
  command = plan

  variables {
    admin_password = "correct-horse-battery-staple"
    ami_id         = "ami-0123456789abcdef0"
    instance_type  = "m7i.large"
  }

  expect_failures = [
    var.instance_type,
  ]
}

run "rejects_small_model_volume" {
  command = plan

  variables {
    admin_password = "correct-horse-battery-staple"
    ami_id         = "ami-0123456789abcdef0"
    volume_size_gb = 19
  }

  expect_failures = [
    var.volume_size_gb,
  ]
}
