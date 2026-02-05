# Clickhouse Configuration Files

These configuration files are baked into the Clickhouse AMI and mounted into the Docker container.

## Files

- **config.xml** - Main Clickhouse server configuration
- **users.xml** - User definitions, profiles, and quotas
- **named_collections.xml** - Named collections for external data sources
- **init-permissions.sql** - SQL script that runs on first container startup

## Usage

1. Replace the placeholder files with your actual Clickhouse configuration
2. Rebuild the AMI: `packer build clickhouse.pkr.hcl`
3. Deploy with Terraform: `tofu apply`

## Configuration Sources

These files should match the configuration from your docker-compose setup:
- `deploy/aws/compose/docker-compose-clickhouse.yaml`

Copy your actual config files from:
```
./data/clickhouse_config/config.xml
./data/clickhouse_config/users.xml
./data/clickhouse_config/named_collections.xml
./data/clickhouse_config/init-permissions.sql
```

## Security Notes

- Ensure passwords and sensitive data are properly secured
- Consider using AWS Secrets Manager for sensitive values
- Review user permissions before deploying to production
