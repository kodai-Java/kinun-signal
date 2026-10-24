# Spot Lab 3-Tier Architecture

This Terraform code provisions a complete, cost-optimized, secure 3-tier architecture on AWS for spot validation purposes.
The infrastructure is designed to be easily deployed for short testing windows and safely, fully torn down without hanging resources or extra costs.

## Features

- **Network**: Multi-AZ (ap-northeast-1a, ap-northeast-1c), isolated subnets, and a single NAT Gateway to reduce cost.
- **Edge**: CloudFront + WAFv2 forwarding to an Application Load Balancer. Direct access to ALB is blocked using a custom secret header condition.
- **Compute**: ECS Fargate running ARM64 containers for cost reduction. ECS Exec is enabled. Container Insights is disabled.
- **Database**: Aurora PostgreSQL Serverless v2 setup with a Writer (1a) and Reader (1c) for failover testing.
- **Ephemerality**: All resources are configured to skip snapshots and ignore deletion protections to ensure `terraform destroy` executes cleanly and rapidly.

## Deployment

1. Ensure you are authenticated with AWS CLI.
2. Initialize Terraform:
   ```bash
   terraform init
   ```
3. (Optional) Provide a custom value for `custom_header_secret` via `terraform.tfvars` or let it use the default.
4. Review the plan:
   ```bash
   terraform plan
   ```
5. Apply the configuration:
   ```bash
   terraform apply
   ```

## Verifying the Deployment

### Web Access

Wait for CloudFront to deploy, then navigate to the URL output by Terraform:

```bash
curl -I https://$(terraform output -raw cloudfront_domain_name)
```
You should see a successful response from the sample `nginxdemos/hello` app.

### Database Connection Testing (ECS Exec)

Because `enable_execute_command = true` is set on the ECS Service, you can open an interactive session directly into one of the Fargate containers and test connectivity to the Aurora database.

1. Find a running Task ID:
   ```bash
   CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
   SERVICE_NAME=$(terraform output -raw ecs_service_name)
   TASK_ID=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --query 'taskArns[0]' --output text | awk -F'/' '{print $3}')
   ```
2. Start an ECS Exec session:
   ```bash
   aws ecs execute-command --cluster $CLUSTER_NAME --task $TASK_ID --container app --interactive --command "/bin/sh"
   ```
3. Inside the container, you can verify connection to Aurora by extracting the endpoint:
   (Note: `nginxdemos/hello` might not have `psql` or `telnet` installed by default. You can install tools or simply use `curl` or `nc` to check if the port is open).

   ```bash
   # Example if apt is available:
   # apt-get update && apt-get install -y postgresql-client
   # PGPASSWORD="<password>" psql -h <writer_endpoint> -U postgres -d spotlabdb -c "\l"
   ```

## Teardown

To avoid incurring any unnecessary costs, destroy the environment as soon as testing is complete. Deletion protections and final snapshots are disabled by design.

```bash
terraform destroy -auto-approve
```
