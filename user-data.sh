#!/bin/bash
# =============================================================================
# Cloud-init user-data script for Private LLM Stack
# Provisions: Docker, Ollama, Open WebUI, Caddy (auto-TLS)
# =============================================================================
set -euo pipefail

# --- Variables (populated by Terraform templatefile) ---
MODEL_NAME="${model_name}"
DOMAIN_NAME="${domain_name}"
ADMIN_USERNAME="${admin_username}"
ADMIN_PASSWORD="${admin_password}"
CADDY_ADDRESS="${caddy_address}"
VOLUME_SIZE_GB="${volume_size_gb}"

# --- Logging ---
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "=== Private LLM Stack cloud-init started at $(date) ==="

# -----------------------------------------------------------------------------
# 1. Mount the model storage volume
# -----------------------------------------------------------------------------
echo "--- Mounting model storage volume ---"
DEVICE="/dev/nvme1n1"
# Fall back to /dev/sdf on non-NVMe instance types
if [ ! -b "$DEVICE" ]; then
  DEVICE="/dev/sdf"
fi

if [ -b "$DEVICE" ]; then
  # Check if already formatted
  if ! blkid "$DEVICE" >/dev/null 2>&1; then
    mkfs.ext4 "$DEVICE"
  fi
  mkdir -p /mnt/models
  echo "$DEVICE /mnt/models ext4 defaults,nofail 0 2" >> /etc/fstab
  mount /mnt/models
  echo "Model volume mounted at /mnt/models"
else
  echo "WARNING: Block device not found, using root volume for model storage"
  mkdir -p /mnt/models
fi

# -----------------------------------------------------------------------------
# 2. Install Docker
# -----------------------------------------------------------------------------
echo "--- Installing Docker ---"
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# -----------------------------------------------------------------------------
# 3. Create Docker network
# -----------------------------------------------------------------------------
echo "--- Creating Docker network ---"
docker network create llm-net 2>/dev/null || true

# -----------------------------------------------------------------------------
# 4. Run Ollama container
# -----------------------------------------------------------------------------
echo "--- Starting Ollama container ---"
docker run -d \
  --name ollama \
  --restart unless-stopped \
  --gpus all \
  --network llm-net \
  -v /mnt/models/ollama:/root/.ollama \
  -p 127.0.0.1:11434:11434 \
  ollama/ollama:latest

# Wait for Ollama to be ready
echo "--- Waiting for Ollama to be ready ---"
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    echo "Ollama is ready"
    break
  fi
  echo "  Waiting for Ollama... ($i/60)"
  sleep 5
done

# -----------------------------------------------------------------------------
# 5. Pull the specified model
# -----------------------------------------------------------------------------
echo "--- Pulling model: $MODEL_NAME ---"
docker exec ollama ollama pull "$MODEL_NAME" &
PULL_PID=$!
# Don't block init on model pull — it can take a while for large models
echo "Model pull started in background (PID: $PULL_PID)"

# -----------------------------------------------------------------------------
# 6. Run Open WebUI container
# -----------------------------------------------------------------------------
echo "--- Starting Open WebUI container ---"
docker run -d \
  --name open-webui \
  --restart unless-stopped \
  --network llm-net \
  -v /mnt/models/open-webui:/app/backend/data \
  -e OLLAMA_BASE_URL=http://ollama:11434 \
  -e WEBUI_AUTH=true \
  -p 127.0.0.1:3000:8080 \
  ghcr.io/open-webui/open-webui:main

# -----------------------------------------------------------------------------
# 7. Install and configure Caddy
# -----------------------------------------------------------------------------
echo "--- Installing Caddy ---"
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy

# Generate htpasswd for basic auth
echo "--- Configuring basic auth ---"
apt-get install -y apache2-utils
HTPASSWD_FILE="/etc/caddy/.htpasswd"
htpasswd -bc "$HTPASSWD_FILE" "$ADMIN_USERNAME" "$ADMIN_PASSWORD"
chmod 640 "$HTPASSWD_FILE"
chown caddy:caddy "$HTPASSWD_FILE"

# Configure Caddy
echo "--- Writing Caddyfile ---"
if [ -n "$DOMAIN_NAME" ]; then
  cat > /etc/caddy/Caddyfile <<CADDYEOF
$CADDY_ADDRESS {
    basicauth {
        import /etc/caddy/.htpasswd
    }
    reverse_proxy 127.0.0.1:3000
}
CADDYEOF
else
  cat > /etc/caddy/Caddyfile <<CADDYEOF
:80 {
    basicauth {
        import /etc/caddy/.htpasswd
    }
    reverse_proxy 127.0.0.1:3000
}
CADDYEOF
fi

# Restart Caddy with new config
systemctl enable caddy
systemctl restart caddy

# -----------------------------------------------------------------------------
# 8. Create systemd service for stack health-check / auto-restart
# -----------------------------------------------------------------------------
echo "--- Creating llm-stack systemd service ---"
cat > /etc/systemd/system/llm-stack.service <<'EOF'
[Unit]
Description=Private LLM Stack Health Check
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/llm-healthcheck.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/llm-healthcheck.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# Ensure Ollama is running
if ! docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
  docker start ollama 2>/dev/null || true
fi

# Ensure Open WebUI is running
if ! docker ps --format '{{.Names}}' | grep -q '^open-webui$'; then
  docker start open-webui 2>/dev/null || true
fi

# Ensure Caddy is running
systemctl is-active --quiet caddy || systemctl start caddy

echo "LLM stack health check passed at $(date)"
EOF

chmod +x /usr/local/bin/llm-healthcheck.sh

# Create a timer for periodic health checks
cat > /etc/systemd/system/llm-stack.timer <<'EOF'
[Unit]
Description=Run LLM stack health check every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable llm-stack.service llm-stack.timer
systemctl start llm-stack.timer

# -----------------------------------------------------------------------------
# 9. Done
# -----------------------------------------------------------------------------
echo "=== Private LLM Stack cloud-init completed at $(date) ==="
echo "Open WebUI will be available at: $${CADDY_ADDRESS}"
echo "Ollama API (local only): http://127.0.0.1:11434"
