# -----------------------------------------------------------------------------
# Input Variables — Private LLM Stack Module
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type. GPU families require an explicit GPU-ready ami_id."
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^(t3\\.|g4dn\\.|g5\\.|p3\\.|p4d\\.)", var.instance_type))
    error_message = "instance_type must be a supported family: t3.*, g4dn.*, g5.*, p3.*, p4d.*."
  }
}

variable "model_name" {
  description = "Ollama model to pull on first boot (e.g. llama3.1:8b, llama3.1:70b, mistral:7b)."
  type        = string
  default     = "llama3.1:8b"
}

variable "domain_name" {
  description = "Fully-qualified domain name for Caddy auto-TLS. Leave empty to use HTTP + Elastic IP."
  type        = string
  default     = ""
}

variable "admin_username" {
  description = "Basic-auth username for the Open WebUI reverse proxy."
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Basic-auth password for the Open WebUI reverse proxy. MUST be set."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "admin_password must be at least 8 characters."
  }
}

variable "route53_zone_name" {
  description = "Public Route53 hosted zone name used when domain_name is set and route53_zone_id is empty (for example, example.com)."
  type        = string
  default     = ""
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach SSH, HTTP, and HTTPS. Restrict to your office/VPN for production."
  type        = list(string)
  default     = []
}

variable "egress_cidrs" {
  description = "CIDR blocks the instance may reach for package, image, certificate, and model downloads. Restrict this through an egress proxy when available."
  type        = list(string)
  default     = []
}

variable "volume_size_gb" {
  description = "EBS volume size (GB) for model storage and container data."
  type        = number
  default     = 100

  validation {
    condition     = var.volume_size_gb >= 20
    error_message = "volume_size_gb must be at least 20 GB."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "private-llm"
}

variable "environment" {
  description = "Environment tag value (e.g. dev, staging, prod)."
  type        = string
  default     = "prod"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance. If empty, the latest Ubuntu 22.04 LTS AMI is looked up automatically."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS record creation. If empty, route53_zone_name must be set."
  type        = string
  default     = ""
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 detailed monitoring (7x cost of standard, but useful for prod)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged into all resources."
  type        = map(string)
  default     = {}
}
