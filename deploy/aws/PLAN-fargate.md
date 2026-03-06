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
- [x] Create `aws_ecs_cluster` resource — added in `fargate.tf`

### Step 2: IAM Roles
- [x] ECS Task Execution Role (pulls images from ECR, writes CloudWatch logs) — `aws_iam_role.ecs_task_execution` with managed policy
- [x] ECS Task Role (permissions the running container needs, if any) — `aws_iam_role.ecs_task` (empty for now)

### Step 3: CloudWatch Log Group
- [x] Create log group for container stdout/stderr — `/ecs/${name_prefix}-seqr-web`, 30 day retention

### Step 4: Security Groups
- [x] ALB security group: allow inbound 80 from `var.allowed_web_cidrs`, outbound all — `aws_security_group.alb`
- [x] ECS service security group: allow inbound 8000 from ALB, outbound all (covers Aurora 5432, Clickhouse 8123/9000, VPC endpoints 443) — `aws_security_group.ecs_service`

### Step 5: Update Existing Security Groups
- [x] Aurora SG: add ingress rule allowing port 5432 from ECS service SG — `aws_security_group_rule.aurora_from_ecs`
- [x] Clickhouse SG: add ingress rules allowing ports 8123 and 9000 from ECS service SG — `aws_security_group_rule.clickhouse_http_from_ecs`, `aws_security_group_rule.clickhouse_native_from_ecs`
- [x] VPC endpoints SG: add ingress rule allowing port 443 from ECS service SG — `aws_security_group_rule.vpc_endpoints_from_ecs`

### Step 6: Application Load Balancer
- [x] ALB resource (public subnets — seqr_az1 and seqr_az2) — `aws_lb.seqr`
- [x] ALB target group (port 8000, IP target type, health check on `/status`) — `aws_lb_target_group.seqr_web`
- [x] ALB listener (port 80 → target group) — `aws_lb_listener.seqr_http`

### Step 7: ECS Task Definition
- [x] Task definition with Fargate compatibility — `aws_ecs_task_definition.seqr_web` (configurable CPU/memory)
- [x] Container definition: image from ECR repo, port 8000, CloudWatch logging
- [x] Environment variables (matched to `settings.py` variable names):
  - `POSTGRES_SERVICE_HOSTNAME` → Aurora cluster endpoint
  - `POSTGRES_SERVICE_PORT` → Aurora cluster port
  - `POSTGRES_USERNAME` → Aurora master username
  - `POSTGRES_PASSWORD` → Aurora master password (sensitive — consider SSM/Secrets Manager later)
  - `CLICKHOUSE_SERVICE_HOSTNAME` → Clickhouse private IP
  - `CLICKHOUSE_SERVICE_PORT` → 9000 (native protocol, as used by django-clickhouse-backend)
  - `REDIS_SERVICE_HOSTNAME` → configurable via variable
  - `REDIS_SERVICE_PORT` → configurable via variable
  - `DEPLOYMENT_TYPE` → environment name
  - `BASE_URL` → ALB DNS name

### Step 8: ECS Service
- [x] Fargate service referencing the task definition — `aws_ecs_service.seqr_web`
- [x] Network configuration: seqr subnets (az1, az2), ECS security group, no public IP
- [x] Load balancer configuration: attached to ALB target group on port 8000
- [x] Desired count: 1 (configurable via `var.seqr_web_desired_count`)

### Step 9: Variables
- [x] `seqr_web_desired_count` (default: 1)
- [x] `seqr_web_cpu` (default: 512 = 0.5 vCPU)
- [x] `seqr_web_memory` (default: 1024 = 1 GB)
- [x] `seqr_web_image_tag` (default: "latest")
- [x] `allowed_web_cidrs` (default: []) — already existed from Step 6
- [x] `redis_service_hostname` (default: "localhost")
- [x] `redis_service_port` (default: 6379)

### Step 10: Outputs
- [x] ALB DNS name — `alb_dns_name` (already existed from Step 6)
- [x] ALB URL — `alb_url` (already existed from Step 6)
- [x] ECS cluster name — `ecs_cluster_name`
- [x] ECS cluster ARN — `ecs_cluster_arn`
- [x] ECS service name — `ecs_service_name`
- [x] ECS task definition ARN — `ecs_task_definition_arn`

## Networking Notes

- Fargate tasks run in the seqr private subnets (az1, az2)
- Fargate tasks need outbound access to ECR (via VPC endpoints already created) and to Aurora/Clickhouse (same VPC)
- ALB sits in the same subnets but with public IP (subnets need internet gateway route)
- **Important**: The seqr subnets were expanded from /28 to /24 (256 IPs each) because ALB requires at least 8 free IPs per subnet. Each Fargate task also consumes an ENI (1 IP). The /24 subnets provide ample room for ALB, Fargate tasks, and future growth.

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
- Secrets management: Aurora password and Clickhouse credentials currently passed as env vars; consider AWS Secrets Manager with `secrets` block in container definition
- Auto-scaling: Can add later based on CPU/memory metrics
- Health check path: Using `/status` (confirmed in ALB target group health check)
- Redis: Deployed as an ECS sidecar container (redis:7-alpine) within the same task definition. Accessible at localhost:6379 with zero network overhead. Uses LRU eviction with 256MB max memory. Appropriate for caching; consider ElastiCache if persistent Redis is needed.
- Django secret key: `DJANGO_KEY` env var not yet set — needs to be provided for production (currently auto-generates a file-based key)
- Clickhouse credentials: `CLICKHOUSE_WRITER_USER`, `CLICKHOUSE_WRITER_PASSWORD`, `CLICKHOUSE_READER_USER`, `CLICKHOUSE_READER_PASSWORD` not yet passed — add when Clickhouse auth is configured
- Additional env vars to consider: `SLACK_TOKEN`, `AIRTABLE_API_KEY`, `GA_TOKEN_ID`, social auth OAuth keys
