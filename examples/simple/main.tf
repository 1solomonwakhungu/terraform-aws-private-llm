# =============================================================================
# Simple Example — Private LLM Stack
# =============================================================================
# Deploy a private LLM with Ollama + Open WebUI behind Caddy TLS.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "private_llm" {
  source = "../.."

  aws_region    = "us-east-1"
  instance_type = "t3.medium"
  model_name    = "llama3.1:8b"

  # Optional: set a domain for auto-TLS via Route53 + Caddy
  # domain_name   = "llm.example.com"
  # route53_zone_id = "Z0123456789ABC"

  admin_username = "admin"
  admin_password = "ChangeMeNow123!" # Use a variable or secrets manager in production

  allowed_cidrs = ["203.0.113.0/24"]
  egress_cidrs  = ["10.0.0.0/8"] # Egress proxy/NAT range.

  volume_size_gb = 100
  project_name   = "private-llm"
  environment    = "prod"

  tags = {
    Owner   = "infra-team"
    Billing = "ai-infra"
  }
}

output "access_url" {
  value = module.private_llm.access_url
}

output "ssh_command" {
  value = module.private_llm.ssh_command
}

output "ollama_api_url" {
  value = module.private_llm.ollama_api_url
}
