# OIDC AWS Deployment Plan

## Objective

Enable Keycloak OIDC authentication for the AWS-deployed seqr instance. OIDC login
is already working in local development (see `plans/OIDC.md`). This plan covers
propagating that configuration to the AWS Fargate infrastructure.

## Prerequisites

- Keycloak realm and client configured with production redirect URI
- Keycloak server reachable from the AWS VPC (see Step 4)
- SSH access from the Keycloak network to the AWS bastion host

---

## Steps

### Step 1: Add Terraform Variables ⬜

**File**: `deploy/aws/variables.tf`

Add variables for OIDC configuration:

| Variable | Type | Sensitive | Default |
|---|---|---|---|
| `social_auth_provider` | string | no | `""` |
| `social_auth_api_url` | string | no | `""` |
| `social_auth_client_id` | string | no | `""` |
| `social_auth_client_secret` | string | yes | `""` |
| `social_auth_keycloak_public_key` | string | yes | `""` |
| `oidc_groups_claim` | string | no | `"ad_groups"` |

### Step 2: Add Environment Variables to Fargate Task Definition ⬜

**File**: `deploy/aws/fargate.tf`

Add to the seqr-web container `environment` block:

- `SOCIAL_AUTH_PROVIDER`
- `SOCIAL_AUTH_API_URL`
- `SOCIAL_AUTH_CLIENT_ID`
- `SOCIAL_AUTH_CLIENT_SECRET`
- `SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY`
- `ARCHIE_OIDC_GROUPS_CLAIM`
- `SOCIAL_AUTH_REDIRECT_IS_HTTPS` (set to `"True"`)

Note: Secrets are passed as plain-text env vars, consistent with how
`aurora_master_password` and `clickhouse_writer_password` are currently handled.
Future improvement: move all sensitive values to AWS Secrets Manager.

### Step 3: Make `SOCIAL_AUTH_REDIRECT_IS_HTTPS` Configurable ⬜

**File**: `settings.py`

Currently hardcoded to `False`. Change to read from environment variable so the
Fargate deployment can set it to `True` (ALB terminates TLS). Without this, the
OAuth callback redirect URI will use `http://` causing a redirect URI mismatch
with Keycloak.

### Step 4: Network Connectivity via Bastion SSH Tunnel ⬜

Fargate tasks run in private subnets with `assign_public_ip = false` and no NAT
Gateway, so they cannot reach the public internet. Keycloak runs on port 8888
and is not directly reachable from the AWS VPC.

**Solution**: Use the bastion host as an SSH tunnel relay. This matches the
existing GCP approach where an SSH reverse tunnel forwards traffic to Keycloak.

#### Architecture

```
Keycloak network                      AWS VPC (private subnets)
┌──────────────────┐  SSH reverse  ┌──────────────┐     ┌─────────────┐
│ keycloak.mcri.   │◄─────────────│   Bastion    │◄────│ ECS Fargate │
│ edu.au:8888      │   tunnel      │   :8888      │     │ (seqr-web)  │
└──────────────────┘               └──────────────┘     └─────────────┘

ECS resolves keycloak.mcri.edu.au → bastion private IP (via extraHosts)
Browser redirects go directly to keycloak.mcri.edu.au:8888 (user's network)
```

#### Sub-steps

**4a. Security group**: Allow ECS service → bastion on port 8888.
Add an ingress rule to the bastion security group allowing TCP 8888 from the
ECS service security group.

**File**: `deploy/aws/main.tf`

**4b. ECS task definition `extraHosts`**: Map `keycloak.mcri.edu.au` to the
bastion's private IP so Django's token exchange reaches the tunnel.

**File**: `deploy/aws/fargate.tf`

Note: The bastion private IP is dynamic (changes on instance replacement). This
is acceptable for now. A future improvement would be to assign a static private
IP to the bastion or use a Route53 private hosted zone.

**4c. Bastion sshd configuration**: Set `GatewayPorts clientspecified` (or `yes`)
in `/etc/ssh/sshd_config` so the reverse tunnel listens on all interfaces, not
just localhost. Restart sshd after the change.

**Manual step** (on bastion):
```bash
echo "GatewayPorts clientspecified" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd
```

**4d. SSH reverse tunnel**: From the Keycloak network, establish the tunnel:
```bash
ssh -R 0.0.0.0:8888:keycloak.mcri.edu.au:8888 ec2-user@<bastion-public-ip>
```

This is a **manual/operational step** that must be running for OIDC to work.
Consider using `autossh` or a systemd service for persistence.

**TLS note**: The tunnel carries raw TCP. The TLS handshake occurs end-to-end
between Django and Keycloak. Since Django resolves `keycloak.mcri.edu.au` to
the bastion IP (via `extraHosts`) and the tunnel transparently forwards to the
real Keycloak server, the TLS certificate validates correctly — the hostname
matches and the certificate chain is intact.

### Step 5: Configure Keycloak Client ⬜

On the Keycloak server, ensure the client is configured with:

- **Valid Redirect URI**: `https://<base_url>/complete/keycloak/`
- **Web Origins**: `https://<base_url>`
- **Client authentication**: Confidential (client secret flow)

### Step 6: Set Values in `terraform.tfvars` ⬜

```hcl
social_auth_provider            = "keycloak"
social_auth_api_url             = "https://keycloak.mcri.edu.au/realms/<realm-name>"
social_auth_client_id           = "<client-id>"
social_auth_client_secret       = "<client-secret>"
social_auth_keycloak_public_key = "<public-key-from-keycloak-realm>"
oidc_groups_claim               = "ad_groups"
```

---

## Files Changed

| File | Change |
|---|---|
| `deploy/aws/variables.tf` | Add 6 OIDC variables + `keycloak_host` |
| `deploy/aws/fargate.tf` | Add 7 env vars + `extraHosts` to seqr-web container |
| `settings.py` | Make `SOCIAL_AUTH_REDIRECT_IS_HTTPS` read from env |
| `deploy/aws/main.tf` | Add bastion ingress rule for port 8888 from ECS |

## Progress Checklist

- [x] Step 1: Add Terraform variables to `deploy/aws/variables.tf`
- [x] Step 2: Add OIDC environment variables + `extraHosts` to Fargate task definition in `deploy/aws/fargate.tf`
- [x] Step 3: Make `SOCIAL_AUTH_REDIRECT_IS_HTTPS` configurable in `settings.py`
- [ ] Step 4a: Add bastion security group ingress for port 8888 from ECS
- [ ] Step 4b: Add `extraHosts` to ECS task definition mapping Keycloak hostname to bastion IP
- [ ] Step 4c: Configure bastion sshd `GatewayPorts` (manual)
- [ ] Step 4d: Establish SSH reverse tunnel from Keycloak network (manual/operational)
- [ ] Step 5: Configure Keycloak client with production redirect URI and origins
- [ ] Step 6: Set OIDC values in `terraform.tfvars`

## Reference

- Local OIDC implementation details: `plans/OIDC.md`
- OIDC architecture overview: `plans/OIDC_OVERVIEW.md`
