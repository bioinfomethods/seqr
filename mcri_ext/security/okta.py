from social_core.backends.open_id_connect import OpenIdConnectAuth

from settings import ARCHIE_OIDC_ENDPOINT


class McriOktaOpenIdConnect(OpenIdConnectAuth):
    """MCRI Okta OpenID-Connect authentication backend"""

    def auth_html(self):
        pass

    name = 'okta-openidconnect'
    REDIRECT_STATE = False
    ACCESS_TOKEN_METHOD = 'POST'
    RESPONSE_TYPE = 'code'
    OIDC_ENDPOINT = ARCHIE_OIDC_ENDPOINT
    DEFAULT_SCOPE = ['openid', 'profile', 'email', 'groups']
