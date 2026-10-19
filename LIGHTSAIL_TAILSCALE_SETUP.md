# Lightsail Tailscale Setup Guide

This document outlines the optimal architecture and configuration steps for running the Personal Stock Analyst application on AWS Lightsail, accessible **only** via Tailscale.

## Architecture Decision

We have chosen the **Host OS installation** approach for Tailscale rather than running it as a Docker sidecar.

**Why Host OS?**
1. **Simplicity of Routing**: Installing Tailscale on the host directly assigns the Tailscale IP to the host's network interfaces. Docker containers mapping ports to `0.0.0.0` or host IPs will automatically be accessible via the Tailscale IP.
2. **Maintenance**: Upgrading Tailscale is handled via the host's package manager (e.g., `apt`), without needing to rebuild or manage sidecar containers.
3. **SSH Access**: Tailscale SSH can be enabled on the host, allowing secure terminal access without opening port 22 on the AWS Lightsail firewall.

## Prerequisites

1. An AWS Lightsail Instance running Ubuntu (provisioned via `deploy_lightsail_private.sh`).
2. A Tailscale account.

## Step 1: Initial Deployment & SSH

Run the deployment script to create the Lightsail instance and configure the initial firewall:

```bash
./deploy_lightsail_private.sh
```

This script will output the public IP of the instance and open SSH (port 22) only for your current IP address.

SSH into the instance (using your Lightsail default key or configured key):

```bash
ssh -i ~/.ssh/LightsailDefaultKey-ap-northeast-1.pem ubuntu@<INSTANCE_PUBLIC_IP>
```

## Step 2: Install Tailscale on the Host

Once logged into the Lightsail instance, run the Tailscale installation script:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Start Tailscale and authenticate. We recommend enabling Tailscale SSH for easier access later:

```bash
sudo tailscale up --ssh
```

Follow the link provided in the terminal to authenticate the node in your Tailscale admin console.

*Note: Once authenticated, note down the Tailscale IP assigned to this instance (e.g., `100.x.y.z`).*

## Step 3: Application Deployment

Clone the application repository onto the Lightsail instance:

```bash
git clone <your-repo-url> stock-analyst
cd stock-analyst
```

Create your `.env` file based on `.env.example`:

```bash
cp .env.example .env
```

**Crucial Step:** Update the `.env` file so the frontend knows where the API is. Set `NEXT_PUBLIC_API_URL` to the **Tailscale IP** of the backend.

```env
# In .env
NEXT_PUBLIC_API_URL=http://<YOUR_TAILSCALE_IP>:8080
```

Start the application using Docker Compose (Docker is pre-installed via the deploy script's user-data):

```bash
# Docker requires sudo unless you re-logged in to apply the 'docker' group
sudo docker compose up -d --build
```

## Step 4: Lightsail Firewall Hardening

Once Tailscale is up and running, you no longer need direct SSH access over the public internet.

1. Go to the AWS Lightsail Console.
2. Select your instance -> **Networking** tab.
3. Under **IPv4 Firewall**, ensure that **all public access is blocked**.
   - **Delete** the rule for SSH (Port 22).
   - Ensure there are **no rules** for HTTP (80), HTTPS (443), Frontend (3000), or Backend (8080).

*Your application is now 100% dark to the public internet.*

## Step 5: Accessing the Application

Ensure the device you are browsing from (your laptop, phone) is connected to your Tailscale network.

Open your browser and navigate to the Next.js frontend using the Lightsail instance's Tailscale IP:

```
http://<YOUR_TAILSCALE_IP>:3000
```

The frontend will make API requests directly to `http://<YOUR_TAILSCALE_IP>:8080`, which is routed securely over the Tailscale mesh network.