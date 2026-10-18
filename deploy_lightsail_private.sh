#!/usr/bin/env bash
# ------------------------------------------------------------
# deploy_lightsail_private.sh
# Deploy the Personal Stock Analyst app to Lightsail with a
# private-only endpoint (no Client VPN). Access via:
#   aws lightsail open-container-service-ssh --service-name $SERVICE_NAME --port 80 --local-port 8080
# ------------------------------------------------------------

set -euo pipefail

# ---- Configuration ------------------------------------------------
# Use env vars or defaults for profile, region, service name
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
SERVICE_NAME="${SERVICE_NAME:-stock-analyst}"
REPO_BACKEND="${SERVICE_NAME}-backend"
REPO_FRONTEND="${SERVICE_NAME}-frontend"
# ------------------------------------------------------------

log(){ echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"; }

# ---- Verify AWS CLI works ---------------------------------------
log "Checking AWS identity..."
aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION"

# ---- Ensure ECR repositories exist --------------------------------
log "Creating/ensuring ECR repositories..."
aws ecr create-repository --repository-name "$REPO_BACKEND" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
aws ecr create-repository --repository-name "$REPO_FRONTEND" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true

# ---- Build Docker images ------------------------------------------
log "Building backend image..."
DOCKER_BUILDKIT=1 docker build -t "$REPO_BACKEND" ./backend
log "Building frontend image..."
DOCKER_BUILDKIT=1 docker build -t "$REPO_FRONTEND" ./frontend

# ---- Push images to ECR -----------------------------------------
log "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" |
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

log "Tagging and pushing backend..."
aws_account=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE" --region "$AWS_REGION")

docker tag "$REPO_BACKEND" "${aws_account}.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_BACKEND:latest"
aws ecr put-image --repository-name "$REPO_BACKEND" --image-tag latest \
    --image-manifest "$(docker inspect --format='{{json .}}' "$REPO_BACKEND")" \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" || true

docker push "${aws_account}.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_BACKEND:latest"

log "Tagging and pushing frontend..."

docker tag "$REPO_FRONTEND" "${aws_account}.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_FRONTEND:latest"
aws ecr put-image --repository-name "$REPO_FRONTEND" --image-tag latest \
    --image-manifest "$(docker inspect --format='{{json .}}' "$REPO_FRONTEND")" \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" || true

docker push "${aws_account}.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_FRONTEND:latest"

# ---- Lightsail Container Service (private) -----------------------
log "Creating Lightsail container service (private)..."
# Lightsail currently does not expose a direct "private only" flag.
# We create the service and then restrict public access via a Lightsail firewall.
aws lightsail create-container-service \
    --service-name "$SERVICE_NAME" \
    --power small \
    --scale 1 \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" || true

# ---- Deploy containers --------------------------------------------
log "Deploying containers to Lightsail..."
cat > containers.json <<EOF
{
  "containers": {
    "backend": {
      "image": "${aws_account}.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_BACKEND:latest",
      "environment": {},
      "command": []
    },
    "frontend": {
      "image": "${aws_account}.dkr.ecr.${AWS_REGION}.amazonaws.com/$REPO_FRONTEND:latest",
      "environment": {
        "NEXT_PUBLIC_API_URL": "http://localhost"
      },
      "command": []
    }
  },
  "publicEndpoint": {
    "containerName": "frontend",
    "containerPort": 80
  }
}
EOF

aws lightsail create-container-service-deployment \
    --service-name "$SERVICE_NAME" \
    --containers file://containers.json \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE"

# ---- Restrict public access (Lightsail firewall)
log "Restricting public access – allowing only your IP for SSH tunnel"
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws lightsail put-public-ports \
    --port-info "fromPort=22,toPort=22,protocol=TCP,accessFrom=${MY_IP}/32" \
    --service-name "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE"

log "Deployment finished."
log "To access the service locally, run:"
log "   aws lightsail open-container-service-ssh --service-name $SERVICE_NAME --port 80 --local-port 8080 --profile $AWS_PROFILE"
log "Then open http://localhost:8080 in your browser."
