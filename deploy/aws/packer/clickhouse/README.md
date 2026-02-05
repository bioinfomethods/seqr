# Clickhouse AMI Builder

This directory contains Packer configuration to build a custom AMI for Clickhouse.

## Quick Start

```bash
# Build AMI with defaults
packer build clickhouse.pkr.hcl

# Or use the helper script
cd ../../scripts
./build-clickhouse-ami.sh
```

## What Gets Installed

The AMI includes:
- Amazon Linux 2023 base
- Docker and AWS CLI
- Clickhouse Docker image (pre-pulled)
- Configuration files in `/opt/clickhouse/config/`
- Systemd service for automatic Clickhouse startup
- Startup script in `/opt/clickhouse/scripts/`

## Directory Structure

```
packer/clickhouse/
├── clickhouse.pkr.hcl          # Packer configuration
├── configs/                     # Configuration files (baked into AMI)
│   ├── config.xml
│   ├── users.xml
│   ├── named_collections.xml
│   └── init-permissions.sql
├── scripts/                     # Scripts (baked into AMI)
│   └── start-clickhouse.sh
└── README.md
```

## Configuration

### Variables

- `aws_region` - AWS region (default: ap-southeast-2)
- `prefix` - Resource prefix (default: mcri)
- `environment` - Environment name (default: dev)
- `clickhouse_version` - Clickhouse Docker image version (default: 25.12)

### Example with Variables

```bash
packer build \
  -var "aws_region=us-east-1" \
  -var "prefix=myorg" \
  -var "environment=prod" \
  -var "clickhouse_version=25.12" \
  clickhouse.pkr.hcl
```

## Customizing Configuration

1. Replace placeholder files in `configs/` with your actual Clickhouse configuration
2. Modify `scripts/start-clickhouse.sh` if needed
3. Rebuild the AMI

## How It Works

1. **Packer launches** a temporary EC2 instance
2. **Installs** Docker, AWS CLI, and dependencies
3. **Copies** configuration files to `/opt/clickhouse/config/`
4. **Pre-pulls** Clickhouse Docker image
5. **Creates** systemd service for automatic startup
6. **Creates AMI** snapshot
7. **Terminates** temporary instance

## Terraform Integration

After building, Terraform automatically detects and uses the latest AMI:

```bash
cd ../..
tofu apply
```

The AMI is selected by:
1. Searching for AMIs with name pattern: `<prefix>-seqr-<environment>-clickhouse-*`
2. Filtering by Environment tag
3. Selecting the most recent

## Troubleshooting

### Packer build fails

```bash
# Validate configuration
packer validate clickhouse.pkr.hcl

# Enable debug logging
PACKER_LOG=1 packer build clickhouse.pkr.hcl
```

### AMI not found by Terraform

Check that:
- AMI was built successfully
- AMI name matches pattern: `<prefix>-seqr-<environment>-clickhouse-*`
- Environment tag matches your tfvars
- AMI is in the correct AWS region

### Instance fails to start Clickhouse

SSH to instance and check:
```bash
# Check systemd service
sudo systemctl status clickhouse

# Check Docker container
sudo docker ps -a
sudo docker logs clickhouse-server

# Check startup script
sudo journalctl -u clickhouse -n 50
```

## Build Time

Typical build time: 5-10 minutes

## Cost

Building an AMI costs only for the temporary EC2 instance runtime (~$0.05 per build).
