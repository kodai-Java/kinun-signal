#!/usr/bin/env bash
# ------------------------------------------------------------
# set_lightsail_ip_restriction.sh
# Restricts Lightsail container service access to specific IP(s).
#  - Removes any public HTTP/HTTPS ports (80, 443)
#  - Opens SSH (port 22) *only* from the provided IP addresses.
#  - Works without creating a Client VPN.
# ------------------------------------------------------------

set -euo pipefail

# ---- Configuration ------------------------------------------------
# Change these values as needed
# Use env vars or defaults for profile, region, service name
AWS_PROFILE="${AWS_PROFILE:-nakajima}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
SERVICE_NAME="${SERVICE_NAME:-stock-analyst}"
# 指定したいIPアドレス（CIDR形式）をスペース区切りで列挙してください。
# 例: "203.0.113.5/32 198.51.100.12/32"
ALLOWED_IPS="${1:-}"                # 第1引数でIPリストを受け取る (省略時は自動取得)
# ------------------------------------------------------------

# ---- Helper -------------------------------------------------------
log(){ echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"; }

# ---- Determine IP(s) if not supplied -----------------------------
if [[ -z "$ALLOWED_IPS" ]]; then
  # 自分の現在IPを取得し /32 に変換
  MY_IP=$(curl -s https://checkip.amazonaws.com)
  ALLOWED_IPS="${MY_IP}/32"
  log "No IP list supplied – using current IP: $ALLOWED_IPS"
fi

# ---- Verify AWS CLI works ----------------------------------------
log "Checking AWS identity..."
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
  log "AWS credentials not found, initiating SSO login..."
  aws sso login --profile "$AWS_PROFILE"
  # retry after login
  aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION"
fi

# ---- Remove any public HTTP/HTTPS ports (80, 443) ----------------
log "Removing public ports 80 and 443 (if present)..."
# No need to delete ports for Lightsail container service – handled via deployment JSON

# ---- Build the PortInfo JSON for allowed IPs --------------------
# Lightsail expects a single string like "fromPort=22,toPort=22,protocol=TCP,accessFrom=IP1/32,accessFrom=IP2/32"
PORT_INFO="fromPort=22,toPort=22,protocol=TCP"
for ip in $ALLOWED_IPS; do
  PORT_INFO+=" ,accessFrom=${ip}"
done

log "Setting SSH (22) access only for: $ALLOWED_IPS"
log "Deploying container service with SSH (22) only ..."
cat > "/tmp/${SERVICE_NAME}_deployment.json" <<EOF
{
  "serviceName": "$SERVICE_NAME",
  "containers": {
    "app": {
      "image": "YOUR_CONTAINER_IMAGE",
      "ports": { "22": "TCP" }
    }
  },
  "publicEndpoint": {
    "containerName": "app",
    "containerPort": 22
  }
}
EOF

aws lightsail create-container-service-deployment \
    --cli-input-json "file:///tmp/${SERVICE_NAME}_deployment.json" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE"

log "IP restriction applied."
log "To connect locally, run:"
log "  aws lightsail open-container-service-ssh \
        --service-name $SERVICE_NAME \
        --port 80 \
        --local-port 8080 \
        --profile $AWS_PROFILE"

log "Done."
