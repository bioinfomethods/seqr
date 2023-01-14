import logging

from oauth2_provider.middleware import OAuth2TokenMiddleware
from social_django.middleware import SocialAuthExceptionMiddleware

log = logging.getLogger(__name__)


class DisableCsrfOAuth2TokenMiddleware:
    """
    Extension of OAuth2TokenMiddleware that disables CSRF (if Bearer token is provided) before delegating to actual
    OAuth2TokenMiddleware().  Bearer tokens themselves are verified with IDP and CSRF is not applicable in this context.
    """

    def __init__(self, get_response):
        self.oauth2_token_middleware = OAuth2TokenMiddleware(get_response)

    def __call__(self, request):
        if request.META.get("HTTP_AUTHORIZATION", "").startswith("Bearer"):
            setattr(request, '_dont_enforce_csrf_checks', True)

        return self.oauth2_token_middleware(request)


class McriSocialAuthExceptionMiddleware(SocialAuthExceptionMiddleware):
    def get_message(self, request, exception):
        user = request.user if hasattr(request, 'user') else None
        if hasattr(request, 'backend') and hasattr(request.backend, 'id_token') and request.backend.id_token:
            user = request.backend.id_token.get('email', None)
        error_msg = 'Error authenticating user {}, error={}'.format(user, str(exception))
        log.error(error_msg, exc_info=exception)

        return error_msg
