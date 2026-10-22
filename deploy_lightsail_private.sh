#!/usr/bin/env bash
# ------------------------------------------------------------
# deploy_lightsail_private.sh
# Deploy the Personal Stock Analyst app to a Lightsail OS instance
# (VPS) rather than the Container Service, to allow for Tailscale
# integration on the Host OS.
# ------------------------------------------------------------

set -euo pipefail

# ---- Configuration ------------------------------------------------
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
INSTANCE_NAME="${INSTANCE_NAME:-stock-analyst-instance}"
BLUEPRINT_ID="${BLUEPRINT_ID:-ubuntu_22_04}"
BUNDLE_ID="${BUNDLE_ID:-medium_2_0}" # 2 vCPU, 4GB RAM is recommended for Rust/Node builds, or small_2_0 for 2GB
# ------------------------------------------------------------

log(){ echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"; }

# ---- Verify AWS CLI works ---------------------------------------
# ---- Verify AWS CLI works ---------------------------------------
log "Checking AWS identity..."
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "AWS credentials not found or SSO not configured."

    # Check if SSO config exists for this profile
    if aws configure get sso_start_url --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log "Attempting SSO login..."
        if [ -n "$AWS_PROFILE" ]; then
            aws sso login --profile "$AWS_PROFILE" || { log "SSO login failed for profile $AWS_PROFILE"; exit 1; }
        else
            aws sso login || { log "SSO login failed for default profile"; exit 1; }
        fi
        # Retry identity check after login
        if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
            log "Failed to verify AWS identity after SSO login."
            exit 1
        fi
    else
        log "⚠️  No SSO configuration found for profile '$AWS_PROFILE'."
        log "Run 'aws configure sso' to set it up, or use a profile with static credentials."
        exit 1
    fi
fi

# ---- Check if instance exists -----------------------------------
log "Checking if Lightsail instance '$INSTANCE_NAME' exists..."
INSTANCE_EXISTS=$(aws lightsail get-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" --query "instances[?name=='$INSTANCE_NAME'].name" --output text)

if [ -z "$INSTANCE_EXISTS" ]; then
    log "Instance not found. Creating new Lightsail instance: $INSTANCE_NAME"

    # User data script to install Docker on first boot
    USER_DATA=$(cat <<'EOF'
#!/bin/bash
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu
EOF
)

    aws lightsail create-instances \
        --instance-names "$INSTANCE_NAME" \
        --availability-zone "${AWS_REGION}a" \
        --blueprint-id "$BLUEPRINT_ID" \
        --bundle-id "$BUNDLE_ID" \
        --user-data "$USER_DATA" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"

    log "Waiting for instance to be running..."
    aws lightsail wait instance-running --instance-name "$INSTANCE_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
    # Allow some time for boot and user-data execution
    sleep 30
else
    log "Instance '$INSTANCE_NAME' already exists."
fi

# ---- Get Instance IP --------------------------------------------
INSTANCE_IP=$(aws lightsail get-instance --instance-name "$INSTANCE_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query "instance.publicIpAddress" --output text)
log "Instance Public IP: $INSTANCE_IP"

# ---- Restrict public access (Lightsail firewall) ----------------
log "Configuring Lightsail firewall..."
# By default, Lightsail might open 22 and 80.
# We want to CLOSE 80/443/3000/8080 to the public, because we will use Tailscale.
# We ONLY open SSH (22) for deployment, ideally restricted to your IP, or Tailscale will handle even SSH later.
MY_IP=$(curl -s https://checkip.amazonaws.com || echo "0.0.0.0")

log "Setting public ports... Allowing SSH from $MY_IP, blocking all direct web access."
aws lightsail put-instance-public-ports \
    --port-infos "fromPort=22,toPort=22,protocol=TCP,cidrs=${MY_IP}/32" \
    --instance-name "$INSTANCE_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE"

log "Deployment infrastructure setup finished."
log "Next Steps:"
log "1. SSH into the instance: ssh -i <your-lightsail-key.pem> ubuntu@$INSTANCE_IP"
log "2. Install Tailscale: curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
log "3. Clone your repo onto the instance and run 'docker compose up -d --build'"
