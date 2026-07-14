# -----------------------------------------------------------------------------
# Outputs — Private LLM Stack Module
# -----------------------------------------------------------------------------

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance (Elastic IP)."
  value       = aws_eip.this.public_ip
}

output "access_url" {
  description = "URL to access Open WebUI (HTTPS with domain or HTTP with IP)."
  value       = local.access_url
}

output "ssh_command" {
  description = "Ready-to-use SSH command to connect to the instance."
  value       = "ssh -o StrictHostKeyChecking=no ubuntu@${aws_eip.this.public_ip}"
}

output "ollama_api_url" {
  description = "Ollama API endpoint (accessible from the instance itself; not exposed externally)."
  value       = "http://127.0.0.1:11434"
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "Security group ID attached to the instance."
  value       = aws_security_group.this.id
}

output "domain_name" {
  description = "The domain name configured for TLS, if any."
  value       = var.domain_name
}
