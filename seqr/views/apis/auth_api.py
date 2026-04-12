"""
Utility functions related to authentication.
"""
import os

from django.contrib.auth import login, authenticate, logout
from django.contrib.auth.decorators import login_required
from django.contrib.auth.models import User
from django.core.exceptions import PermissionDenied
from django.db.models.functions import Lower
from django.shortcuts import redirect

import json

from seqr.utils.logging_utils import SeqrLogger
from seqr.views.utils.json_utils import create_json_response
from seqr.views.utils.terra_api_utils import oauth_enabled, remove_token
from settings import LOGIN_URL, POLICY_REQUIRED_URL

logger = SeqrLogger(__name__)


def test_login_view(request):
    """Test-only login endpoint that bypasses OIDC. Only available when ENABLE_TEST_LOGIN=true."""
    if not os.environ.get('ENABLE_TEST_LOGIN'):
        raise PermissionDenied('Test login is not enabled')

    request_json = json.loads(request.body)
    if not request_json.get('email'):
        return create_json_response({'error': 'Email is required'}, status=400, reason='Email is required')

    email_lower = request_json['email'].lower()
    users = User.objects.annotate(email_lower=Lower('email')).filter(email_lower=email_lower)
    if users.count() == 0:
        # Auto-create user for test purposes (only reachable when ENABLE_TEST_LOGIN is set)
        user = User.objects.create_user(
            username=email_lower,
            email=email_lower,
            is_staff=True,
            is_superuser=True,
        )
        user.set_unusable_password()
        user.save()
        users = User.objects.filter(pk=user.pk)
    if users.count() != 1:
        return create_json_response({'error': 'Invalid credentials'}, status=401, reason='Invalid credentials')

    user = users.first()
    if request_json.get('password'):
        u = authenticate(username=user.username, password=request_json['password'])
        if not u:
            return create_json_response({'error': 'Invalid credentials'}, status=401, reason='Invalid credentials')
    else:
        u = user

    login(request, u, backend='django.contrib.auth.backends.ModelBackend')
    logger.info('Test login: {}'.format(u.email), u)
    return create_json_response({'success': True})


def login_view(request):
    if oauth_enabled():
        raise PermissionDenied('Username/ password authentication is disabled')

    request_json = json.loads(request.body)
    if not request_json.get('email'):
        error = 'Email is required'
        return create_json_response({'error': error}, status=400, reason=error)
    if not request_json.get('password'):
        error = 'Password is required'
        return create_json_response({'error': error}, status=400, reason=error)

    # Django's iexact filtering will improperly match unicode characters, which creates a security risk.
    # Instead, query for the lower case match to allow case-insensitive matching
    users = User.objects.annotate(email_lower=Lower('email')).filter(email_lower=request_json['email'].lower())
    if users.count() != 1:
        error = 'Invalid credentials'
        return create_json_response({'error': error}, status=401, reason=error)

    user = users.first()
    u = authenticate(username=user.username, password=request_json['password'])
    if not u:
        error = 'Invalid credentials'
        return create_json_response({'error': error}, status=401, reason=error)

    login(request, u)
    logger.info('Logged in {}'.format(u.email), u)

    return create_json_response({'success': True})


@login_required(login_url='/', redirect_field_name=None)
def logout_view(request):
    user = request.user
    remove_token(user)
    logout(request)
    logger.info('Logged out {}'.format(user.email), user)
    return redirect('/')


def app_login_required_error(request, exception=None):
    """Redirect to login for unhandled 401 error on non-API request"""
    return redirect(f'{LOGIN_URL}?next={request.path}')


def login_required_error(request):
    """Returns an HttpResponse with a 401 UNAUTHORIZED error message.

    This is used to redirect AJAX HTTP handlers to the login page.
    """
    return _unauthorized_error(LOGIN_URL)


def policies_required_error(request):
    """Returns an HttpResponse with a 401 UNAUTHORIZED error message.

    This is used to redirect AJAX HTTP handlers to the accept policies page.
    """
    return _unauthorized_error(POLICY_REQUIRED_URL)


def _unauthorized_error(error_redirect):
    error = error_redirect.split('/')[1]
    return create_json_response({'error': error_redirect} , status=401, reason="{} required".format(error))
