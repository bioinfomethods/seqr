# Plan: ECS Fargate for seqr-web (Django)

## Overview

Deploy the seqr-web Django application as an ECS Fargate service behind an ALB.
The service connects to both Aurora PostgreSQL and the Clickhouse EC2 instance.

## Architecture

```
Internet → ALB (port 80/443) → ECS Fargate Service (port 8000) → Aurora PostgreSQL (port 5432)
                                                                 → Clickhouse EC2 (port 8123/9000)
```

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Launch type | Fargate | Serverless, no EC2 management |
| File location | `fargate.tf` (sibling file) | Clean separation, TF merges all .tf files |
| Container port | 8000 | Standard Django port |
| ALB | Yes, public-facing | HTTP/HTTPS ingress to Django |
| Module? | No | Inline in fargate.tf |

## Implementation Steps

### Step 1: ECS Cluster
- [ ] Create `aws_ecs_cluster` resource

### Step 2: IAM Roles
- [ ] ECS Task Execution Role (pulls images from ECR, writes CloudWatch logs)
- [ ] ECS Task Role (permissions the running container needs, if any)

### Step 3: CloudWatch Log Group
- [ ] Create log group for container stdout/stderr

### Step 4: Security Groups
- [ ] ALB security group: allow inbound 80/443 from internet, outbound to ECS
- [ ] ECS service security group: allow inbound 8000 from ALB, outbound to Aurora (5432), Clickhouse (8123/9000), and VPC endpoints (443 for ECR image pull)

### Step 5: Update Existing Security Groups
- [ ] Aurora SG: add ingress rule allowing port 5432 from ECS service SG
- [ ] Clickhouse SG: add ingress rules allowing ports 8123 and 9000 from ECS service SG

### Step 6: Application Load Balancer
- [ ] ALB resource (public subnets — use seqr_az1 and seqr_az2)
- [ ] ALB target group (port 8000, health check on Django health endpoint)
- [ ] ALB listener (port 80 → target group; HTTPS can be added later)

### Step 7: ECS Task Definition
- [ ] Task definition with Fargate compatibility
- [ ] Container definition: image from ECR repo, port 8000, environment variables for DB connections
- [ ] Environment variables needed:
  - `DATABASE_HOST` → Aurora cluster endpoint
  - `DATABASE_PORT` → 5432
  - `DATABASE_NAME` → Aurora database name
  - `DATABASE_USER` → Aurora master username
  - `DATABASE_PASSWORD` → Aurora master password (sensitive — use SSM/Secrets Manager or pass via variable)
  - `CLICKHOUSE_HOST` → Clickhouse private IP
  - `CLICKHOUSE_PORT` → 8123

### Step 8: ECS Service
- [ ] Fargate service referencing the task definition
- [ ] Network configuration: seqr subnets, ECS security group, no public IP (traffic via ALB)
- [ ] Load balancer configuration: attach to ALB target group
- [ ] Desired count: 1 (can scale later)

### Step 9: Variables
- [ ] Add new variables to `variables.tf`:
  - `seqr_web_desired_count` (default: 1)
  - `seqr_web_cpu` (default: 512 = 0.5 vCPU)
  - `seqr_web_memory` (default: 1024 = 1 GB)
  - `seqr_web_image_tag` (default: "latest")
  - `allowed_web_cidrs` (default: ["0.0.0.0/0"] or restricted)

### Step 10: Outputs
- [ ] Add outputs to `outputs.tf`:
  - ALB DNS name
  - ALB URL
  - ECS cluster name
  - ECS service name

## Networking Notes

- Fargate tasks run in the seqr private subnets (az1, az2)
- Fargate tasks need outbound access to ECR (via VPC endpoints already created) and to Aurora/Clickhouse (same VPC)
- ALB sits in the same subnets but with public IP (subnets need internet gateway route)
- **Important**: The seqr subnets are /28 (16 IPs each). Each Fargate task consumes an ENI (1 IP). This limits scaling but is fine for initial deployment.

## Dependencies on Existing Resources (from main.tf)

- `aws_ecr_repository.seqr_web` — image source
- `module.aurora` — database endpoint, port, credentials
- `aws_instance.clickhouse` — private IP for Clickhouse connection
- `aws_subnet.seqr_az1`, `aws_subnet.seqr_az2` — networking
- `aws_security_group.clickhouse` — needs additional ingress from ECS
- Aurora security group (via module) — needs additional ingress from ECS
- VPC endpoints for ECR — already exist

## Open Questions / Future Work

- HTTPS: Need ACM certificate + Route53 domain to add HTTPS listener
- Secrets management: Aurora password currently passed as variable; consider AWS Secrets Manager
- Auto-scaling: Can add later based on CPU/memory metrics
- Health check path: Need to confirm Django health check endpoint (e.g., `/health/` or `/status/`)
- Additional environment variables: seqr may need more config (Redis, etc.)
