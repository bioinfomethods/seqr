import jwt
from social_core.backends.keycloak import KeycloakOAuth2

from settings import OIDC_GROUPS_CLAIM


class McriKeycloakOAuth2(KeycloakOAuth2):  # pylint: disable=abstract-method
    """MCRI Keycloak OAuth2 authentication backend

    Changed DEFAULT_SCOPE to include openid, authenticated results now include id_token where groups can be
    extracted.  This is necessary to keep access_token small.
    """

    def auth_html(self):
        pass

    name = 'keycloak'
    ID_KEY = 'username'
    ACCESS_TOKEN_METHOD = 'POST'
    DEFAULT_SCOPE = ['openid', 'profile', 'email', 'ad_groups', 'offline_access']

    def user_data(self, access_token, *args, **kwargs):  # pylint: disable=unused-argument
        result = jwt.decode(
            access_token,
            key=self.public_key(),
            algorithms=self.algorithm(),
            audience=self.audience(),
        )

        if 'response' in kwargs and 'id_token' in kwargs['response']:
            id_token = kwargs['response']['id_token']
            data = jwt.decode(
                id_token,
                key=self.public_key(),
                algorithms=self.algorithm(),
                audience=self.audience(),
            )
            keep = {key: data[key] for key in data.keys() if key in [OIDC_GROUPS_CLAIM]}
            result.update(keep)

        return result
