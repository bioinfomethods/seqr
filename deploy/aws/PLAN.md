# Seqr AWS Implementation Plan

This file contains the HIGH LEVEL steps for implementing the Seqr
AWS infrastructure.

Refer to `CONVENTIONS.md` for overall guidance and `INFRA_ARCHITECTURE.md` for the 
architecture.

In this file:

- define overall high level steps to complete
- track progress in implementing these steps

## Implementation Strategy

We will build the infrastructure incrementally, testing each component before moving forward.
The order follows logical dependencies: foundation → data layer → compute layer → access layer.

## Plan

### Phase 0: Foundation & Configuration
**Status**: Complete

- [x] **0.1** Create base Terraform configuration structure
  - Main configuration files (main.tf, variables.tf, outputs.tf)
  - Provider configuration (AWS provider, backend for S3 state)
  - Define ONLY basic variables (region, prefix, environment, cost_centre, vpc_id)
  
- [x] **0.2** Create environment-specific tfvars template
  - Document only required basic variables
  - Create minimal terraform-dev.tfvars.example
  
- [x] **0.3** Set up tagging module/locals
  - Default tags (Environment, CostCentre)
  - Name tag generation logic
  
- [x] **0.4** Set up VPC and subnet data sources
  - Query default VPC or use provided VPC ID
  - Query subnets in the VPC
  
- [x] **0.5** Test: Validate configuration initializes and plans successfully

**Notes/Decisions**:
- Simplified Phase 0 to only include basics: tagging, environment, state bucket, VPC/subnets
- Removed all component-specific variables (bastion, aurora, clickhouse, ecs, etc.)
- These will be added incrementally in later phases as needed
- Set up backend configuration for S3 state storage with DynamoDB locking
- Implemented local variables for name_prefix and default_tags
- Added VPC data sources to query default VPC and subnets
- Used AWS provider ~> 5.0 for latest features
- All resources will use default_tags from provider configuration
- Created setup-backend.sh script to automate S3 bucket and DynamoDB table creation
- Region set to ap-southeast-2 (Sydney)

---

### Phase 1: Networking Foundation
**Status**: Complete

- [x] **1.1** Configure VPC data source (using default VPC)
  - Query default VPC
  - Query default subnets
  - Query availability zones
  
- [x] **1.2** Create dedicated subnets for seqr infrastructure
  - CIDR AZ1: 172.31.254.0/28 (16 IP addresses)
  - CIDR AZ2: 172.31.254.16/28 (16 IP addresses)
  - Placed in first two available AZs (required for Aurora)
  
- [x] **1.3** Create security group for bastion host
  - Allow SSH (port 22) from configurable CIDR ranges
  - Allow all outbound traffic
  - Dynamic ingress rules based on allowed_ssh_cidrs variable
  
- [x] **1.4** Test: Verify subnet and security group creation

**Notes/Decisions**:
- Created two dedicated /28 subnets (16 IPs each) for seqr infrastructure
- Two subnets required for Aurora (must span at least 2 AZs)
- Subnet CIDRs are configurable via variables (defaults: 172.31.254.0/28 and 172.31.254.16/28)
- Changed from 172.31.255.x to 172.31.254.x due to conflict with existing subnet
- Security group uses dynamic blocks to support multiple allowed SSH CIDR ranges
- All egress traffic allowed from bastion for flexibility

---

### Phase 2: Bastion Host (Access Layer)
**Status**: Complete

- [x] **2.1** Create bastion host EC2 instance
  - Using Amazon Linux 2023 AMI (latest via data source)
  - Instance type: t3.micro for dev
  - Attached security group from Phase 1
  - SSH key pair: id_ed25519_mcri_aws
  - Placed in dedicated seqr subnet
  
- [x] **2.2** Create Elastic IP for bastion
  - Associated with bastion instance
  - Output the public IP
  
- [x] **2.3** Test: SSH into bastion host successfully

**Notes/Decisions**:
- Using Amazon Linux 2023 (latest stable version)
- AMI is auto-selected via data source, but can be overridden with bastion_ami_id variable
- Instance gets public IP automatically and EIP for stable addressing
- SSH key name configurable via variable (default: id_ed25519_mcri_aws)
- Added output for convenient SSH command
- SSH user: ec2-user
- Successfully tested SSH connection to bastion host

---

### Phase 3: Database Layer - Aurora PostgreSQL
**Status**: Complete

- [x] **3.1** Create security group for Aurora
  - Allow PostgreSQL (port 5432) from bastion security group
  - Will add ECS security group access in Phase 6
  
- [x] **3.2** Create Aurora PostgreSQL cluster
  - Subnet group using dedicated seqr subnets in 2 AZs
  - Master username: seqr (configurable)
  - Database name: seqrdb (configurable)
  - Engine: aurora-postgresql 15.5
  - Backup retention: 7 days (configurable)
  
- [x] **3.3** Create Aurora instance(s)
  - One writer instance
  - Instance class: db.t3.medium for dev (configurable)
  
- [ ] **3.4** Test: Connect to Aurora from bastion host using psql

**Notes/Decisions**:
- Using Aurora PostgreSQL 15.5 (version 15.4 not available in ap-southeast-2)
- Master username set to "seqr" as requested
- Database name set to "seqrdb" as requested
- Instance class configurable via variable (default: db.t3.medium for dev)
- Skip final snapshot enabled for dev (should be false for production)
- Security group currently allows access from bastion only
- Will add ECS security group ingress rule in Phase 6
- Backup window set to 03:00-04:00 UTC
- Aurora subnet group uses dedicated seqr subnets spanning 2 AZs (required by Aurora)

---

### Phase 4: Container Registry (ECR)
**Status**: Not Started

- [ ] **4.1** Create ECR repository for seqr-web (Django)
  - Configure image scanning
  - Set lifecycle policies
  
- [ ] **4.2** Create ECR repository for clickhouse (if custom image needed)
  
- [ ] **4.3** Test: Push a test image to ECR repository

**Notes/Decisions**:

---

### Phase 5: Clickhouse Database (EC2)
**Status**: Not Started

- [ ] **5.1** Create security group for Clickhouse
  - Allow Clickhouse port (8123 HTTP, 9000 native) from ECS security group
  - Allow Clickhouse ports from bastion security group
  - Allow SSH from bastion security group
  
- [ ] **5.2** Create EC2 instance for Clickhouse
  - Use pre-configured AMI (or create launch template)
  - Instance type (m5.xlarge or appropriate for workload)
  - Attach security group
  - User data script to start Clickhouse container
  
- [ ] **5.3** Configure EBS volume for Clickhouse data
  - Attach and mount volume
  
- [ ] **5.4** Test: Connect to Clickhouse from bastion, verify container running

**Notes/Decisions**:

---

### Phase 6: ECS Cluster & Task Definition
**Status**: Not Started

- [ ] **6.1** Create ECS cluster
  - Fargate launch type
  
- [ ] **6.2** Create security group for ECS tasks
  - Allow HTTP (port 8000 or Django port) from ALB security group
  - Allow outbound to Aurora security group (port 5432)
  - Allow outbound to Clickhouse security group (ports 8123, 9000)
  - Allow outbound to internet (for package downloads, etc.)
  
- [ ] **6.3** Create IAM role for ECS task execution
  - ECR pull permissions
  - CloudWatch logs permissions
  
- [ ] **6.4** Create IAM role for ECS task
  - Any AWS service permissions Django needs
  
- [ ] **6.5** Create CloudWatch log group for Django container
  
- [ ] **6.6** Create ECS task definition for seqr-web
  - Container definition with ECR image
  - Environment variables for Aurora connection
  - Environment variables for Clickhouse connection
  - Resource limits (CPU, memory)
  - Log configuration
  
- [ ] **6.7** Test: Run task manually, verify it starts and logs appear

**Notes/Decisions**:

---

### Phase 7: Application Load Balancer
**Status**: Not Started

- [ ] **7.1** Create security group for ALB
  - Allow HTTP (port 80) from bastion security group only
  - Allow HTTPS (port 443) from bastion security group only (if using SSL)
  - Allow outbound to ECS security group
  
- [ ] **7.2** Create ALB
  - Internal load balancer (not internet-facing)
  - Attach to default VPC subnets
  - Attach security group
  
- [ ] **7.3** Create target group for ECS service
  - Target type: IP
  - Health check configuration for Django
  
- [ ] **7.4** Create ALB listener
  - Forward to target group
  
- [ ] **7.5** Test: Verify ALB is created and healthy

**Notes/Decisions**:

---

### Phase 8: ECS Service
**Status**: Not Started

- [ ] **8.1** Create ECS service
  - Use task definition from Phase 6
  - Desired count (1 for dev, more for prod)
  - Attach to ALB target group
  - Configure service discovery (optional)
  
- [ ] **8.2** Configure auto-scaling (optional, for prod)
  
- [ ] **8.3** Test: Verify service starts, tasks are healthy, registered with ALB

**Notes/Decisions**:

---

### Phase 9: End-to-End Testing
**Status**: Not Started

- [ ] **9.1** Test SSH tunnel through bastion to ALB
  - Set up local port forwarding
  
- [ ] **9.2** Test Django application access through tunnel
  - Verify web interface loads
  
- [ ] **9.3** Test Django → Aurora connectivity
  - Verify database queries work
  
- [ ] **9.4** Test Django → Clickhouse connectivity
  - Verify analytics queries work
  
- [ ] **9.5** Document access procedures

**Notes/Decisions**:

---

### Phase 10: Documentation & Cleanup
**Status**: Not Started

- [ ] **10.1** Create README with deployment instructions
  
- [ ] **10.2** Document environment variable requirements
  
- [ ] **10.3** Create runbook for common operations
  
- [ ] **10.4** Review and optimize resource configurations
  
- [ ] **10.5** Final security review

**Notes/Decisions**:

---

## Progress Tracking

- **Current Phase**: Phase 3 (Testing)
- **Last Updated**: 2026-02-03
- **Blockers**: None
- **Next Steps**: Test PostgreSQL connection from bastion, then begin Phase 4 - ECR

