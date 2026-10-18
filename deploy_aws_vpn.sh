#!/usr/bin/env bash
# ------------------------------------------------------------
# Personal Stock Analyst – AWS VPN‑only low‑cost deployment script
# ------------------------------------------------------------
set -euo pipefail

# ---------- Configuration ----------
REGION="ap-northeast-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BACKEND="stock-analyst-backend"
ECR_FRONTEND="stock-analyst-frontend"
VPC_CIDR="10.0.0.0/16"
PRIVATE_SUBNET_CIDR="10.0.1.0/24"
PUBLIC_SUBNET_CIDR="10.0.2.0/24"
VPN_CLIENT_CIDR="10.0.3.0/22"
DB_PASSWORD="MySuperSecret123!"
FMP_API_KEY="mock_fmp_key"
LLM_API_KEY="mock_llm_key"
LINE_TOKEN="mock_line_token"

# ---------- 1. ECR repositories ----------
aws ecr create-repository --repository-name $ECR_BACKEND --region $REGION || true
aws ecr create-repository --repository-name $ECR_FRONTEND --region $REGION || true
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# ---------- 2. Build & push Docker images ----------
 echo "== Building backend image =="
 docker build -t $ECR_BACKEND ./backend
 docker tag $ECR_BACKEND:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_BACKEND:latest
 docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_BACKEND:latest

 echo "== Building frontend image =="
 docker build -t $ECR_FRONTEND ./frontend
 docker tag $ECR_FRONTEND:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_FRONTEND:latest
 docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_FRONTEND:latest

# ---------- 3. Create self‑signed certificates for VPN ----------
 mkdir -p ./vpn_certs && cd vpn_certs
 openssl genrsa -out server.key 2048
 openssl req -new -key server.key -subj "/CN=vpn-server" -out server.csr
 openssl x509 -req -days 3650 -in server.csr -signkey server.key -out server.crt
 SERVER_CERT_ARN=$(aws acm import-certificate \
   --certificate fileb://server.crt \
   --private-key fileb://server.key \
   --region $REGION \
   --query CertificateArn --output text)

 openssl genrsa -out client_root.key 2048
 openssl req -new -x509 -key client_root.key -subj "/CN=vpn-client-root" -days 3650 -out client_root.crt
 CLIENT_ROOT_CERT_ARN=$(aws acm import-certificate \
   --certificate fileb://client_root.crt \
   --private-key fileb://client_root.key \
   --region $REGION \
   --query CertificateArn --output text)
 cd ..

# ---------- 4. CloudFormation stack (VPC, RDS, VPN) ----------
 cat > infra.yml <<'EOF'
AWSTemplateFormatVersion: "2010-09-09"
Description: Personal Stock Analyst – VPN‑only low‑cost infra
Parameters:
  VpcCidr:               { Type: String, Default: "10.0.0.0/16" }
  PrivateSubnetCidr:     { Type: String, Default: "10.0.1.0/24" }
  PublicSubnetCidr:      { Type: String, Default: "10.0.2.0/24" }
  VpnClientCidr:         { Type: String, Default: "10.0.3.0/22" }
  DbPassword:            { Type: String, NoEcho: true }
  VpnServerCertArn:      { Type: String }
  VpnClientRootCertArn:  { Type: String }
Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsSupport: true
      EnableDnsHostnames: true
  PrivateSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Ref PrivateSubnetCidr
      MapPublicIpOnLaunch: false
  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Ref PublicSubnetCidr
      MapPublicIpOnLaunch: true
  VpnOnlySG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Allow inbound from VPN CIDR only
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: !Ref VpnClientCidr
        - IpProtocol: tcp
          FromPort: 8080
          ToPort: 8080
          CidrIp: !Ref VpnClientCidr
  DBSubnetGroup:
    Type: AWS::RDS::DBSubnetGroup
    Properties:
      DBSubnetGroupDescription: Stock Analyst DB subnet group
      SubnetIds:
        - !Ref PrivateSubnet
  DBInstance:
    Type: AWS::RDS::DBInstance
    DeletionPolicy: Delete
    Properties:
      DBInstanceIdentifier: stock-analyst-db
      Engine: postgres
      EngineVersion: "16"
      DBInstanceClass: db.t4g.micro
      AllocatedStorage: 20
      MasterUsername: postgres
      MasterUserPassword: !Ref DbPassword
      VPCSecurityGroups:
        - !GetAtt VpnOnlySG.GroupId
      DBSubnetGroupName: !Ref DBSubnetGroup
      PubliclyAccessible: false
  ClientVpnEndpoint:
    Type: AWS::EC2::ClientVpnEndpoint
    Properties:
      ServerCertificateArn: !Ref VpnServerCertArn
      AuthenticationOptions:
        - Type: certificate-authentication
          MutualAuthentication:
            ClientRootCertificateChainArn: !Ref VpnClientRootCertArn
      ClientCidrBlock: !Ref VpnClientCidr
      ConnectionLogOptions:
        Enabled: true
        CloudwatchLogGroup: !Ref VpnLogGroup
      VpcId: !Ref VPC
      SecurityGroupIds:
        - !GetAtt VpnOnlySG.GroupId
  VpnLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      RetentionInDays: 30
Outputs:
  RdsEndpoint:          { Value: !GetAtt DBInstance.Endpoint.Address }
  ClientVpnEndpointId:  { Value: !Ref ClientVpnEndpoint }
EOF

 aws cloudformation create-stack \
   --stack-name stock-analyst-infra \
   --template-body file://infra.yml \
   --parameters ParameterKey=DbPassword,ParameterValue=$DB_PASSWORD \
                ParameterKey=VpnServerCertArn,ParameterValue=$SERVER_CERT_ARN \
                ParameterKey=VpnClientRootCertArn,ParameterValue=$CLIENT_ROOT_CERT_ARN \
   --capabilities CAPABILITY_NAMED_IAM \
   --region $REGION
 echo "Waiting for CloudFormation stack…"
 aws cloudformation wait stack-create-complete --stack-name stock-analyst-infra --region $REGION

 RDS_ENDPOINT=$(aws cloudformation describe-stacks --stack-name stock-analyst-infra --region $REGION \
   --query "Stacks[0].Outputs[?OutputKey=='RdsEndpoint'].OutputValue" --output text)
 VPN_ENDPOINT_ID=$(aws cloudformation describe-stacks --stack-name stock-analyst-infra --region $REGION \
   --query "Stacks[0].Outputs[?OutputKey=='ClientVpnEndpointId'].OutputValue" --output text)

# ---------- 5. Lightsail container service ----------
 aws lightsail create-container-service --service-name stock-analyst --power small --scale 1 --region $REGION

 cat > containers.json <<EOF
{
  "containers": {
    "backend": {
      "image": "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_BACKEND:latest",
      "environment": {
        "DATABASE_URL": "postgres://postgres:$DB_PASSWORD@$RDS_ENDPOINT:5432/stock_analyst",
        "FMP_API_KEY": "$FMP_API_KEY",
        "LLM_API_KEY": "$LLM_API_KEY",
        "LINE_CHANNEL_ACCESS_TOKEN": "$LINE_TOKEN",
        "LLM_MODEL": "argon"
      },
      "ports": { "8080": "HTTP" }
    },
    "frontend": {
      "image": "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_FRONTEND:latest",
      "environment": { "NEXT_PUBLIC_API_URL": "http://backend:8080" },
      "ports": { "80": "HTTP" }
    }
  },
  "publicEndpoint": { "containerName": "frontend", "containerPort": 80 }
}
EOF

 aws lightsail create-container-service-deployment --service-name stock-analyst --containers file://containers.json --region $REGION

# ---------- 6. VPN authorization & client config ----------
 aws ec2 create-client-vpn-authorization-rule \
   --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
   --target-network-cidr $VPC_CIDR \
   --authorize-all-groups \
   --region $REGION
 aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id $VPN_ENDPOINT_ID --output text > vpn-config.ovpn

 echo "Deployment complete."
 echo "VPN client config: $(pwd)/vpn-config.ovpn"
 echo "Access the app (VPN only) at: https://stock-analyst.service.$REGION.lightsail.amazonaws.com"
EOF
