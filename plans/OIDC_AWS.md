# OIDC AWS Deployment Plan

## Objective

Enable Keycloak OIDC authentication for the AWS-deployed seqr instance. OIDC login
is already working in local development (see `plans/OIDC.md`). This plan covers
propagating that configuration to the AWS Fargate infrastructure.

## Prerequisites

- Keycloak realm and client configured with production redirect URI
- Keycloak server reachable from the AWS VPC (see Step 4)

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

### Step 4: Verify Network Connectivity (Fargate → Keycloak) ⬜

Fargate tasks run in private subnets with `assign_public_ip = false`. The ECS
security group allows all outbound traffic, but without a public IP the tasks
cannot reach the internet via the IGW alone.

**Decision required**: Is Keycloak on the public internet or reachable within the VPC?

- **Public internet**: Need a NAT Gateway (add to `deploy/aws/main.tf`), or set
  `assign_public_ip = true` on the ECS service
- **Internal/VPC-reachable**: Verify routing exists from the seqr subnets

This is the most likely blocker — ECR pulls currently work only because of VPC
endpoints, not because the tasks have general internet access.

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

### Step 7: Security Verification ⬜

- Confirm `ENABLE_TEST_LOGIN` is **NOT** set in the Fargate task environment
- Review whether `create_user` should remain in `SOCIAL_AUTH_PIPELINE` for
  production (currently any Keycloak-authenticated user gets a Django account
  auto-created)
- Note: logout only destroys the Django session, not the Keycloak session (no
  back-channel/front-channel logout implemented)

### Step 8: Deploy and Test ⬜

1. `terraform plan` — verify only expected changes
2. `terraform apply`
3. Test full login flow: browser → Keycloak → callback → dashboard
4. Test logout flow
5. Verify group synchronisation works with production Keycloak groups

---

## Files Changed

| File | Change |
|---|---|
| `deploy/aws/variables.tf` | Add 6 OIDC variables |
| `deploy/aws/fargate.tf` | Add 7 env vars to seqr-web container |
| `settings.py` | Make `SOCIAL_AUTH_REDIRECT_IS_HTTPS` read from env |
| `deploy/aws/main.tf` | Potentially add NAT Gateway (if Keycloak is external) |

## Reference

- Local OIDC implementation details: `plans/OIDC.md`
- OIDC architecture overview: `plans/OIDC_OVERVIEW.md`
