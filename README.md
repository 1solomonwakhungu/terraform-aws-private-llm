# Private LLM Stack — Terraform Module

[![Terraform CI](https://github.com/1solomonwakhungu/terraform-aws-private-llm/actions/workflows/terraform.yml/badge.svg?branch=main)](https://github.com/1solomonwakhungu/terraform-aws-private-llm/actions/workflows/terraform.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A production-grade Terraform module that deploys a complete **private LLM infrastructure** on AWS in under 20 minutes.

## What This Module Deploys

| Component       | Technology                          | Purpose                                      |
|-----------------|-------------------------------------|----------------------------------------------|
| LLM Engine      | [Ollama](https://ollama.ai)         | Serves open-weight models (Llama 3.1, Mistral, etc.) |
| Web UI          | [Open WebUI](https://open-webui.github.io/) | ChatGPT-style interface for the LLM   |
| Reverse Proxy   | [Caddy](https://caddyserver.com)    | Auto-TLS, basic auth, request proxying       |
| Container Runtime | Docker                            | Isolates and manages all services            |
| Compute         | AWS EC2 (GPU or CPU)               | Runs the inference workload                  |
| Storage         | EBS gp3 (encrypted)                | Model weights and persistent data            |
| DNS / TLS       | Route53 + Caddy ACME               | Automatic HTTPS certificate provisioning     |

## Architecture Overview

```
                    ┌─────────────────────────────────────────────┐
                    │              Internet / Client               │
                    └──────────────────┬──────────────────────────┘
                                       │
                              ┌────────▼────────┐
                              │  Route53 (A)     │  ← Conditional (if domain set)
                              │  llm.example.com │
                              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │  Elastic IP     │
                              │  (Static Public)│
                              └────────┬────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │         EC2 Instance (g5.xlarge)        │
                    │                                         │
                    │  ┌─────────┐  ┌──────────┐  ┌────────┐ │
                    │  │ Caddy   │  │ Open WebUI│  │ Ollama │ │
                    │  │ :80/:443│─▶│ :3000    │─▶│ :11434 │ │
                    │  │ TLS+Auth│  │ Web UI   │  │  LLM   │ │
                    │  └─────────┘  └──────────┘  └────────┘ │
                    │                                         │
                    │  ┌────────────────────────────────────┐ │
                    │  │  Docker (network: llm-net)         │ │
                    │  └────────────────────────────────────┘ │
                    │                                         │
                    │  ┌────────────────────────────────────┐ │
                    │  │  EBS gp3 (encrypted, /mnt/models)  │ │
                    │  │  Model weights + persistent data   │ │
                    │  └────────────────────────────────────┘ │
                    └─────────────────────────────────────────┘
```

## Prerequisites

1. **AWS CLI** — configured with credentials that can create EC2, EIP, Route53, and Security Group resources.
   ```bash
   aws configure
   ```

2. **Terraform** ≥ 1.5.0
   ```bash
   brew tap hashicorp/tap && brew install hashicorp/tap/terraform
   ```

3. **Route53 Hosted Zone** (optional, for TLS) — your domain must have a hosted zone in Route53.
   ```bash
   aws route53 list-hosted-zones
   ```

4. **GPU AMI Compatibility** — if using `g5.*` instances, ensure your AWS account has GPU instance limits.
   ```bash
   aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA
   ```

## Usage

### Basic (no domain, HTTP only)

```hcl
module "private_llm" {
  source = "github.com/1solomonwakhungu/terraform-aws-private-llm"

  aws_region     = "us-east-1"
  instance_type  = "g5.xlarge"
  model_name     = "llama3.1:8b"
  admin_username = "admin"
  admin_password = "SuperSecretPass123!"

  allowed_cidrs = ["203.0.113.0/24"]  # Your office IP range
}
```

### With domain and auto-TLS

```hcl
module "private_llm" {
  source = "github.com/1solomonwakhungu/terraform-aws-private-llm"

  aws_region      = "us-east-1"
  instance_type   = "g5.xlarge"
  model_name      = "llama3.1:70b"
  domain_name     = "llm.mycompany.com"
  route53_zone_id = "Z0123456789ABCDEF"

  admin_username = "admin"
  admin_password = "SuperSecretPass123!"

  volume_size_gb = 200
  allowed_cidrs  = ["10.0.0.0/8"]  # VPN/internal only
}
```

### Apply

```bash
terraform init
terraform plan
terraform apply
```

After apply completes (5-10 min for cloud-init), visit the `access_url` output.

## Requirements

| Name      | Version   |
|-----------|-----------|
| terraform | >= 1.5.0  |
| aws       | >= 5.0    |
| random    | >= 3.5    |

## Providers

| Name   | Version |
|--------|---------|
| aws    | >= 5.0  |
| random | >= 3.5  |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aws_region | AWS region for all resources. | `string` | `"us-east-1"` | No |
| instance_type | EC2 instance type. Use `g5.xlarge` for GPU acceleration or `t3.medium` for CPU-only. | `string` | `"g5.xlarge"` | No |
| model_name | Ollama model to pull on first boot (e.g. `llama3.1:8b`, `llama3.1:70b`, `mistral:7b`). | `string` | `"llama3.1:8b"` | No |
| domain_name | Fully-qualified domain name for Caddy auto-TLS. Leave empty to use HTTP + Elastic IP. | `string` | `""` | No |
| admin_username | Basic-auth username for the Open WebUI reverse proxy. | `string` | `"admin"` | No |
| admin_password | Basic-auth password for the Open WebUI reverse proxy. Must be at least 8 characters. | `string` | n/a | **Yes** |
| allowed_cidrs | CIDR blocks allowed to reach SSH, HTTP, and HTTPS. Restrict to your office/VPN for production. | `list(string)` | `["0.0.0.0/0"]` | No |
| volume_size_gb | EBS volume size (GB) for model storage and container data (minimum 20). | `number` | `100` | No |
| project_name | Project name used for resource naming and tagging. | `string` | `"private-llm"` | No |
| environment | Environment tag value (e.g. `dev`, `staging`, `prod`). | `string` | `"prod"` | No |
| ami_id | AMI ID for the EC2 instance. If empty, the latest Ubuntu 22.04 LTS AMI is looked up automatically. | `string` | `""` | No |
| route53_zone_id | Route53 hosted zone ID for DNS record creation. If empty and `domain_name` is set, the zone is looked up by domain suffix. | `string` | `""` | No |
| enable_detailed_monitoring | Enable EC2 detailed monitoring (higher cost, but useful for prod). | `bool` | `true` | No |
| tags | Additional tags merged into all resources. | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| instance_public_ip | Public IP address of the EC2 instance (Elastic IP). |
| access_url | URL to access Open WebUI (HTTPS with domain or HTTP with IP). |
| ssh_command | Ready-to-use SSH command to connect to the instance. |
| ollama_api_url | Ollama API endpoint (accessible from the instance itself; not exposed externally). |
| instance_id | EC2 instance ID. |
| security_group_id | Security group ID attached to the instance. |
| domain_name | The domain name configured for TLS, if any. |

## Cost Breakdown by Tier

| Tier          | Instance      | Model          | Compute/mo | Storage/mo | **Total/mo** | Client Price | **Margin/mo** |
|---------------|---------------|----------------|------------|------------|-------------|-------------|--------------|
| **Starter**   | t3.medium     | llama3.1:8b    | ~$30       | ~$10       | **~$40**    | $250        | **$210**     |
| **Professional** | g5.xlarge  | llama3.1:70b   | ~$550      | ~$20       | **~$570**   | $750        | **$180**     |
| **Enterprise**| g5.2xlarge    | llama3.1:70b+  | ~$1,100    | ~$40       | **~$1,140** | $2,000      | **$860**     |

> **Notes:**
> - Compute costs assume 24/7 on-demand pricing in `us-east-1`. Reserved instances reduce cost 30-60%.
> - Enterprise tier assumes HA setup (2 instances + load balancer) — multiply compute by ~2x.
> - Egress and Route53 query costs are minimal (<$5/mo typical).
> - Model pull time: 8B ≈ 5 min, 70B ≈ 40 min (depending on bandwidth).

## 60-Second Demo Script

See [`demo-script.md`](./demo-script.md) for the standalone sales call demo.

## Customization

| Variable              | Default          | Description                                      |
|-----------------------|------------------|--------------------------------------------------|
| `instance_type`       | `g5.xlarge`      | Any `t3.*`, `g4dn.*`, `g5.*`, `p3.*`, `p4d.*`   |
| `model_name`          | `llama3.1:8b`    | Any Ollama model tag (e.g. `mistral:7b`, `codellama:13b`) |
| `volume_size_gb`      | `100`            | Increase for larger models (70B needs ~80GB)    |
| `allowed_cidrs`       | `["0.0.0.0/0"]`  | Lock down to office/VPN IPs in production       |
| `domain_name`         | `""`             | Set for auto-TLS via Caddy + Route53            |
| `enable_detailed_monitoring` | `true`   | CloudWatch 1-minute metrics                     |
| `tags`                | `{}`             | Additional resource tags                        |

### Supported Models

| Model              | Min VRAM | Recommended Instance | Notes                        |
|--------------------|----------|---------------------|------------------------------|
| `llama3.1:8b`      | 6 GB     | t3.medium (CPU) or g5.xlarge | Fast, good for general use |
| `mistral:7b`       | 6 GB     | t3.medium or g5.xlarge       | Great reasoning/JSON      |
| `llama3.1:70b`     | 40 GB    | g5.xlarge (quantized) or g5.2xlarge | High quality, slower |
| `codellama:13b`    | 10 GB    | g5.xlarge                    | Code generation           |
| `nomic-embed-text` | 1 GB     | t3.medium                    | Embeddings for RAG        |

## Security Considerations

1. **Restrict `allowed_cidrs`** — The default `0.0.0.0/0` is for quick starts only. Always set to your office/VPN CIDR in production.

2. **Basic auth is enabled** — Caddy protects Open WebUI with HTTP basic auth. For stronger security, consider:
   - Adding OAuth2/OIDC via Caddy plugins
   - Using AWS WAF in front
   - Putting the instance behind a VPN (WireGuard, Tailscale)

3. **Ollama API is local-only** — The Ollama container binds to `127.0.0.1:11434`, not exposed externally. Only Open WebUI (via Caddy) is accessible.

4. **EBS volumes are encrypted** — All EBS volumes use AWS-managed encryption (KMS). For compliance, use customer-managed CMKs.

5. **No secrets in user-data** — The `admin_password` is passed via `templatefile()`. For production, consider:
   - AWS Secrets Manager + a bootstrap script that fetches the password at runtime
   - SSM Parameter Store with IAM role-based access

6. **GPU instance security** — GPU instances are high-value targets. Use:
   - IAM instance profiles with minimal permissions
   - AWS Systems Manager Session Manager instead of SSH where possible
   - Regular security patching (the AMI is Ubuntu 22.04 LTS, auto-updates via unattended-upgrades)

7. **Network isolation** — Consider deploying in a private subnet with a NAT gateway for production. This module uses the default VPC for simplicity.

## File Structure

```
private-llm/
├── versions.tf          # Provider requirements
├── variables.tf         # Input variables
├── main.tf              # Resources (EC2, SG, EIP, Route53)
├── outputs.tf           # Module outputs
├── user-data.sh         # Cloud-init script (Docker, Ollama, Open WebUI, Caddy)
├── examples/
│   └── simple/
│       └── main.tf      # Simple usage example
├── demo-script.md       # 60-second sales demo script
└── README.md            # This file
```

## License

MIT License. See [`LICENSE`](./LICENSE).
