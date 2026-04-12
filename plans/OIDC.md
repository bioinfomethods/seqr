# MCRI Keycloak OIDC Integration

## Objective

Add support for login to MCRI seqr via integration with Keycloak OIDC.

## Background

Keycloak integration was ALREADY implemented in a separate branch. The changes were
CHERRY PICKED from that branch since significant code drift made a straight merge
impossible. Merge conflicts were resolved manually.

## Current Status: ✅ Working (Local Development)

OIDC login via Keycloak is fully working in the local docker-compose development
environment. Users can authenticate through Keycloak and are redirected back to seqr
with a valid session. The dashboard loads and projects are accessible.

### What's Working

- **Keycloak OIDC login flow**: Full redirect to Keycloak, authentication, and
  callback to seqr with session creation
- **User auto-creation**: New users authenticating via Keycloak are created in Django
  automatically via the `social_core.pipeline.user.create_user` pipeline step
- **Group synchronisation**: The `associate_groups` pipeline step syncs OIDC group
  claims (configurable via `ARCHIE_OIDC_GROUPS_CLAIM`) to Django groups on login
- **E2E test infrastructure**: Playwright tests with authenticated session injection
  via a test-only login endpoint (`/api/test_login`)
- **Seqr Policies acceptance flow**: Works correctly after OIDC login

### Key Issues Overcome

1. **Missing imports in `social_auth_pipeline.py`**: Bad cherry-pick left `logging`
   and `re` modules unimported. The file had duplicate logger assignments from
   conflicting merge artifacts (`SeqrLogger` vs `logging.getLogger`). Fixed by
   cleaning up to use standard `logging` module only.

2. **Keycloak client credentials (401 on token exchange)**: The initial 401 error
   from Keycloak's token endpoint was caused by incorrect `SOCIAL_AUTH_CLIENT_SECRET`
   configuration — the secret didn't match what was configured in the Keycloak realm.
   Fixed by correcting the environment variable value.

3. **E2E test login**: Created a dedicated `/api/test_login` endpoint gated behind
   `ENABLE_TEST_LOGIN=true` environment variable. This endpoint:
   - Bypasses OIDC entirely for test automation
   - Auto-creates a superuser if the test user doesn't exist
   - Is used by Playwright's `globalSetup` to obtain an authenticated session
   - Session is saved via `storageState` and injected into all authenticated tests

4. **Semantic UI checkbox interaction**: The Seqr Policies acceptance checkbox uses
   a hidden `<input>` with a `<label>` overlay (Semantic UI pattern). Playwright's
   `.check()` fails because the label intercepts pointer events. Fixed by clicking
   the label text directly instead.

### Important Configuration

Key environment variables for Keycloak OIDC (set in `docker-compose.yml`):

| Variable | Purpose | Example |
|---|---|---|
| `SOCIAL_AUTH_PROVIDER` | Backend identifier | `keycloak` |
| `SOCIAL_AUTH_API_URL` | Keycloak realm URL | `https://keycloak.mcri.edu.au:8888/realms/bioinfomethods-test` |
| `SOCIAL_AUTH_CLIENT_ID` | Keycloak client ID | `archietest` |
| `SOCIAL_AUTH_CLIENT_SECRET` | Keycloak client secret | *(sensitive)* |
| `SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY` | Realm public key | *(from Keycloak admin)* |
| `ARCHIE_OIDC_GROUPS_CLAIM` | OIDC claim for group sync | `ad_groups` |
| `ENABLE_TEST_LOGIN` | Enable test login endpoint | `true` (local/CI only) |

### E2E Test Architecture

- **`tests/e2e/global-setup.ts`**: Authenticates via `/api/test_login`, saves session
  to `tests/e2e/auth.json`
- **`tests/e2e/playwright.config.ts`**: Two projects:
  - `authenticated` — uses saved `storageState`, ignores login tests
  - `unauthenticated` — runs only `login_test.spec.ts` without session
- **`ENABLE_TEST_LOGIN`** must be set in the Django container (not the Playwright host)

### Security Notes

- `ENABLE_TEST_LOGIN=true` **must NOT be set in production** — it allows passwordless
  login and auto-creates superuser accounts
- The `SOCIAL_AUTH_PIPELINE` includes `create_user`, meaning anyone who authenticates
  via Keycloak gets a Django user created automatically. Verify this is intentional
  for production, or move `validate_user_exist` earlier in the pipeline to restrict
  access to pre-created users only.

## Next Steps

- **AWS deployment**: The Terraform infrastructure in `deploy/aws/` has not been
  updated to include OIDC/Keycloak support. The Fargate task definition and
  environment variables need to be configured with the Keycloak settings. This is
  the next objective.
- **Group sync validation**: Verify that Keycloak group claims are correctly mapped
  to Django groups and that project permissions work as expected.
- **Production pipeline hardening**: Review `SOCIAL_AUTH_PIPELINE` ordering for
  production use — consider whether `validate_user_exist` should gate access before
  `create_user`.
