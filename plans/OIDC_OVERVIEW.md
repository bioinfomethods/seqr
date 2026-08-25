# OIDC Authentication Implementation Guide

## Overview

This file describes how a previous impelementation of OIDC connected to Keycloak works, in order
to guide the porting of that functionality into this instance of the application.

The application uses **Keycloak** as an OIDC identity provider for browser-based user login. The integration is built on top
of **python-social-auth** (`social_django`) with a custom Keycloak backend. Keycloak may broker authentication to upstream identity providers (e.g., Okta, Entra ID), but from the application's perspective, it only communicates with Keycloak.

### High-Level Flow

```
Browser → /login/keycloak
  → 302 to Keycloak authorization endpoint
  → User authenticates (possibly brokered to Okta/Entra ID)
  → 302 callback to /complete/keycloak/ with authorization code
  → social_django exchanges code for tokens
  → Social auth pipeline runs (match/create user, sync data, log)
  → Django session created, session cookie set
  → 302 redirect to /
```

---

## Files Involved

### Core Authentication Backend

| File | Purpose |
|---|---|
| `mcri_ext/security/keycloak.py` | Custom Keycloak OAuth2 backend extending `social_core.backends.keycloak.KeycloakOAuth2`. Decodes both `access_token` and `id_token` JWTs. Extracts the groups claim from the `id_token` to keep the `access_token` small. |

### Social Auth Pipeline

| File | Purpose |
|---|---|
| `mcri_ext/security/social_auth_pipeline.py` | MCRI-specific pipeline steps: `associate_by_email_or_username` (matches OIDC identity to existing Django user by email or username), `associate_groups` (syncs IdP groups to Django groups — **not currently in the active pipeline**), `validate_user_exist` (MCRI version, redirects to `/login` if no user), `log_authentication`. |
| `seqr/utils/social_auth_pipeline.py` | Upstream seqr pipeline steps used in the active pipeline: `validate_user_exist` (redirects to `/login/error/no_account`), `log_signed_in` (audit logging). Also contains `validate_anvil_registration` and `log_azure_signed_in` which are **not used** in the Keycloak flow. |

### Middleware

| File | Purpose |
|---|---|
| `mcri_ext/security/security_middleware.py` | `DisableCsrfOAuth2TokenMiddleware` — disables CSRF for Bearer token requests (not relevant to browser login but is in the middleware chain). `McriSocialAuthExceptionMiddleware` — catches `social_core` exceptions during the OIDC flow and logs them with user context. |
| `seqr/utils/middleware.py` | `JsonErrorMiddleware` — converts exceptions (including `AuthException` → 401) to JSON responses for API requests, or delegates to Django's error handling for page requests. `LogRequestMiddleware` — logs all requests. `CacheControlMiddleware` — sets no-cache headers. |

### URL Configuration

| File | Purpose |
|---|---|
| `seqr/urls.py` | Includes `social_django.urls` at the root path (`path('', include('social_django.urls'))`), which provides `/login/keycloak`, `/complete/keycloak/`, `/disconnect/keycloak/`, etc. Also defines the `/logout` route and login-required error handlers. |

### Views

| File | Purpose |
|---|---|
| `seqr/views/apis/auth_api.py` | `login_view` — username/password login, **disabled** when OAuth is enabled (raises `PermissionDenied`). `logout_view` — clears stored OAuth tokens and destroys Django session, redirects to `/`. `login_required_error` / `policies_required_error` — return 401 JSON responses for unauthenticated API requests. |
| `seqr/views/react_app.py` | `render_app_html` — injects `oauthLoginProvider` (value: `'keycloak'`) into the page's `initialJSON` so the frontend knows which login flow to present. Also injects current user data if authenticated. |
| `mcri_ext/views/apis/users_api.py` | `get_user` — returns current authenticated user's profile JSON. Protected by `@login_and_policies_required`. |

### Token/Session Utilities

| File | Purpose |
|---|---|
| `seqr/views/utils/terra_api_utils.py` | `oauth_enabled()` — returns `True` if `SOCIAL_AUTH_PROVIDER` is set (always true in practice). `remove_token()` — clears stored access token from the `social_auth` user record on logout. `_safe_get_social()` — retrieves the `social_auth` association for the current provider. |

### Settings

| File | Purpose |
|---|---|
| `settings.py` | All OIDC configuration: authentication backends, social auth pipeline, Keycloak endpoints, scopes, middleware ordering, login URLs. |

---

## Settings Reference

### Authentication Backends

```python
AUTHENTICATION_BACKENDS = (
    'social_core.backends.google.GoogleOAuth2',           # Not used in Keycloak flow
    'oauth2_provider.backends.OAuth2Backend',             # Bearer token introspection (API only)
    'mcri_ext.security.keycloak.McriKeycloakOAuth2',      # ← Keycloak browser login
    'django.contrib.auth.backends.ModelBackend',          # Django built-in (password auth, disabled)
    'guardian.backends.ObjectPermissionBackend',           # Object-level permissions
)
```

### Keycloak OIDC Settings

```python
# Base URL of the Keycloak realm (e.g. https://keycloak.example.com/realms/myrealm)
SOCIAL_AUTH_API_URL = os.environ.get('SOCIAL_AUTH_API_URL', 'https://dev-000000.okta.com/oauth2/default')

# OIDC client credentials
SOCIAL_AUTH_CLIENT_ID = os.environ.get('SOCIAL_AUTH_CLIENT_ID')
SOCIAL_AUTH_CLIENT_SECRET = os.environ.get('SOCIAL_AUTH_CLIENT_SECRET')

# Keycloak public key for JWT verification
SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY = os.environ.get('SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY')

# Mapped to social_core Keycloak backend settings
SOCIAL_AUTH_KEYCLOAK_API_URL = SOCIAL_AUTH_API_URL
SOCIAL_AUTH_KEYCLOAK_KEY = SOCIAL_AUTH_CLIENT_ID
SOCIAL_AUTH_KEYCLOAK_SECRET = SOCIAL_AUTH_CLIENT_SECRET

# Keycloak OIDC endpoints (derived from API_URL)
SOCIAL_AUTH_KEYCLOAK_AUTHORIZATION_URL = f"{SOCIAL_AUTH_KEYCLOAK_API_URL}/protocol/openid-connect/auth"
SOCIAL_AUTH_KEYCLOAK_ACCESS_TOKEN_URL = f"{SOCIAL_AUTH_KEYCLOAK_API_URL}/protocol/openid-connect/token"
```

### Scopes and Claims

```python
# Scopes requested from Keycloak
OIDC_SCOPE = ['openid', 'profile', 'email', 'ad_groups', 'groups', 'offline_access']
SOCIAL_AUTH_KEYCLOAK_SCOPE = OIDC_SCOPE

# The claim name in the id_token that contains group memberships
OIDC_GROUPS_CLAIM = os.environ.get('ARCHIE_OIDC_GROUPS_CLAIM', 'ad_groups')
```

### Social Auth General Settings

```python
SOCIAL_AUTH_PROVIDER = os.environ.get('SOCIAL_AUTH_PROVIDER', 'google-oauth2')  # Set to 'keycloak' for MCRI
SOCIAL_AUTH_JSONFIELD_ENABLED = True
SOCIAL_AUTH_URL_NAMESPACE = 'social'
SOCIAL_AUTH_LOGIN_REDIRECT_URL = '/'
SOCIAL_AUTH_REDIRECT_IS_HTTPS = False  # Set to True in production behind TLS termination
```

### Login URL

```python
# When Google OAuth2 key is not set (MCRI Keycloak deployment), LOGIN_URL = '/login'
SOCIAL_AUTH_GOOGLE_OAUTH2_KEY = os.environ.get('SOCIAL_AUTH_GOOGLE_OAUTH2_CLIENT_ID')
LOGIN_URL = GOOGLE_LOGIN_REQUIRED_URL if SOCIAL_AUTH_GOOGLE_OAUTH2_KEY else '/login'
# GOOGLE_LOGIN_REQUIRED_URL = '/login/google-oauth2'
```

### Social Auth Pipeline

The **active pipeline** (MCRI override at the bottom of `settings.py`):

```python
SOCIAL_AUTH_PIPELINE = (
    'social_core.pipeline.social_auth.social_details',                  # 1
    'social_core.pipeline.social_auth.social_uid',                      # 2
    'social_core.pipeline.social_auth.social_user',                     # 3
    'social_core.pipeline.social_auth.load_extra_data',                 # 4
    'mcri_ext.security.social_auth_pipeline.associate_by_email_or_username',  # 5
    'social_core.pipeline.user.create_user',                            # 6
    'social_core.pipeline.user.user_details',                           # 7
    'social_core.pipeline.social_auth.associate_user',                  # 8
    'seqr.utils.social_auth_pipeline.validate_user_exist',              # 9
    'seqr.utils.social_auth_pipeline.log_signed_in',                    # 10
)
```

### Middleware (Auth-Related, in Order)

```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'mcri_ext.security.security_middleware.DisableCsrfOAuth2TokenMiddleware',  # ← CSRF bypass for Bearer tokens
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.middleware.common.CommonMiddleware',
    'csp.middleware.CSPMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'seqr.utils.middleware.CacheControlMiddleware',
    'seqr.utils.middleware.LogRequestMiddleware',
    'seqr.utils.middleware.JsonErrorMiddleware',
    'mcri_ext.security.security_middleware.McriSocialAuthExceptionMiddleware',  # ← Social auth error handling
]
```

### Required Django Apps

```python
INSTALLED_APPS = [
    ...
    'social_django',        # python-social-auth Django integration
    'oauth2_provider',      # django-oauth-toolkit (for Bearer token introspection)
    'mcri_ext',             # MCRI extensions (Keycloak backend, pipeline, middleware)
    ...
]
```

### Environment Variables Summary

| Variable | Required | Description |
|---|---|---|
| `SOCIAL_AUTH_PROVIDER` | Yes | Set to `keycloak` |
| `SOCIAL_AUTH_API_URL` | Yes | Keycloak realm URL (e.g. `https://keycloak.example.com/realms/myrealm`) |
| `SOCIAL_AUTH_CLIENT_ID` | Yes | OIDC client ID registered in Keycloak |
| `SOCIAL_AUTH_CLIENT_SECRET` | Yes | OIDC client secret |
| `SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY` | Yes | RSA public key from Keycloak realm for JWT verification |
| `ARCHIE_OIDC_GROUPS_CLAIM` | No | Claim name for groups in the id_token (default: `ad_groups`) |

---

## Detailed Flow

### 1. User Visits Protected Page

Any page decorated with `@login_active_required(login_url=LOGIN_URL)` (e.g., `main_app` in `react_app.py`) redirects unauthenticated users. For API endpoints, `login_required_error` returns a 401 JSON response with the login URL.

### 2. Redirect to Keycloak

`social_django` handles `/login/keycloak` by redirecting the browser to:
```
{SOCIAL_AUTH_KEYCLOAK_AUTHORIZATION_URL}?
  response_type=code&
  client_id={SOCIAL_AUTH_KEYCLOAK_KEY}&
  redirect_uri={BASE_URL}/complete/keycloak/&
  scope=openid profile email ad_groups groups offline_access&
  state={csrf_state}
```

### 3. User Authenticates

The user authenticates at Keycloak (which may broker to Okta or Entra ID). On success, Keycloak redirects back to `/complete/keycloak/?code=...&state=...`.

### 4. Token Exchange

`social_django` exchanges the authorization code for tokens by POSTing to `SOCIAL_AUTH_KEYCLOAK_ACCESS_TOKEN_URL`. The response includes:
- `access_token` (JWT)
- `id_token` (JWT, contains groups claim)
- `refresh_token` (because `offline_access` scope was requested)

### 5. Custom Backend: `McriKeycloakOAuth2.user_data()`

The custom backend in `mcri_ext/security/keycloak.py` processes the tokens:

```python
def user_data(self, access_token, *args, **kwargs):
    # Decode access_token for user profile data
    result = jwt.decode(access_token, key=self.public_key(), algorithms=self.algorithm(),
                        audience=self.audience(), leeway=30)

    # Also decode id_token to extract groups claim
    if 'response' in kwargs and 'id_token' in kwargs['response']:
        id_token = kwargs['response']['id_token']
        data = jwt.decode(id_token, key=self.public_key(), algorithms=self.algorithm(),
                          audience=self.audience(), leeway=30)
        keep = {key: data[key] for key in data.keys() if key in [OIDC_GROUPS_CLAIM]}
        result.update(keep)

    return result
```

Key design decisions:
- **`ID_KEY = 'username'`**: Users are identified by their Keycloak username, not the `sub` claim.
- **Groups are in the `id_token`**, not the `access_token`, to keep the access token small.
- **`leeway=30`**: 30-second clock skew tolerance for JWT validation.

### 6. Pipeline Execution

Each step in order:

| Step | Function | What It Does |
|---|---|---|
| 1 | `social_details` | Extracts `email`, `username`, `first_name`, `last_name` from the `user_data()` result into a `details` dict. |
| 2 | `social_uid` | Extracts the unique user ID using `ID_KEY` (`username`). |
| 3 | `social_user` | Looks up an existing `UserSocialAuth` record matching this provider + UID. If found, the associated Django `User` is attached. |
| 4 | `load_extra_data` | Stores token data (`access_token`, `refresh_token`, `expires`, `auth_time`, etc.) in `UserSocialAuth.extra_data`. |
| 5 | `associate_by_email_or_username` | **MCRI custom.** If no user was found in step 3, queries `User.objects.filter(Q(username__iexact=email) \| Q(email__iexact=email))`. Returns the matched user or `None`. Raises `AuthException` if multiple users match. **This is safe only because the IdP is trusted and users cannot self-register.** |
| 6 | `create_user` | If still no user, creates a new Django `User` from the OIDC details. |
| 7 | `user_details` | Updates the Django `User` fields (first name, last name, email) from the OIDC details. |
| 8 | `associate_user` | Creates the `UserSocialAuth` link between the Django `User` and the Keycloak social identity. |
| 9 | `validate_user_exist` | Safety check: if there is still no user after all previous steps, redirects to `/login/error/no_account`. |
| 10 | `log_signed_in` | Logs `'Logged in {email} (keycloak)'`. If the user was just created, also logs `'Created user {email} (keycloak)'`. |

### 7. Session Created

After the pipeline completes successfully, `social_django` logs the user in (creates a Django session) and redirects to `SOCIAL_AUTH_LOGIN_REDIRECT_URL` (`/`).

### 8. Frontend Loads

`render_app_html` in `react_app.py` serves the SPA with:
```python
initial_json = {'meta': {
    'oauthLoginProvider': 'keycloak',  # Frontend uses this to show correct login button
    ...
}}
```
The frontend can call `GET /api/users/current` to fetch the authenticated user's profile.

### 9. Logout

`GET /logout` triggers:
1. `remove_token(user)` — clears `access_token` from `UserSocialAuth.extra_data`, sets `expires = 0`
2. `logout(request)` — destroys the Django session
3. Redirects to `/`

**Important**: There is no OIDC back-channel or front-channel logout. The Keycloak session remains active. If the user visits `/login/keycloak` again, they may be silently re-authenticated via their existing Keycloak session.

---

## Error Handling

| Scenario | Handler | Result |
|---|---|---|
| OIDC callback fails (e.g., invalid state, token error) | `McriSocialAuthExceptionMiddleware` | Logs error with user context, returns error message |
| `AuthException` raised in pipeline (e.g., duplicate email match) | `JsonErrorMiddleware` | Returns 401 for API requests; delegates to Django error handler for page requests |
| No existing user and pipeline can't create one | `validate_user_exist` | Redirects to `/login/error/no_account` |
| User tries password login when OAuth is enabled | `login_view` | Raises `PermissionDenied` → 403 |

---

## Dependencies

### Python Packages

- `social-auth-app-django` (`social_django`) — Django integration for python-social-auth
- `social-auth-core` (`social_core`) — Core social auth library, includes `KeycloakOAuth2` backend
- `PyJWT` (`jwt`) — JWT decoding in the custom Keycloak backend
- `django-oauth-toolkit` (`oauth2_provider`) — In the middleware chain but not used for browser login

### Django Apps Required

```python
'social_django'     # Provides UserSocialAuth model, URL routes, context processors
'oauth2_provider'   # Required because DisableCsrfOAuth2TokenMiddleware wraps OAuth2TokenMiddleware
'mcri_ext'          # Custom Keycloak backend, pipeline steps, middleware
```

### Database Tables

`social_django` creates these tables (via migrations):
- `social_auth_usersocialauth` — Links Django users to social provider identities, stores tokens
- `social_auth_nonce` — OIDC nonce tracking
- `social_auth_association` — OpenID associations
- `social_auth_code` — Authorization codes

### Template Context Processors

```python
'social_django.context_processors.backends'        # Makes social auth backends available in templates
'social_django.context_processors.login_redirect'   # Makes login redirect URL available in templates
```
