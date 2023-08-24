import logging
import re

from django.conf import settings
from django.contrib.auth.models import User, Group
from django.db.models import Q
from django.shortcuts import redirect
from social_core.exceptions import AuthException

from settings import OIDC_GROUPS_CLAIM

log = logging.getLogger(__name__)


def validate_user_exist(backend, response, user=None, *args, **kwargs):
    if not user:
        log.warning('User {} is trying to login without an existing account ({}).'.format(
            response['email'], backend.name))
        return redirect('/login')


def associate_groups(backend, response, user, details, *args, **kwargs):
    if user:
        log.info('Associating %s to user %s', OIDC_GROUPS_CLAIM, user.email)
        ad_groups = details.get(OIDC_GROUPS_CLAIM,
                                response.get(OIDC_GROUPS_CLAIM,
                                             response.get('groups',
                                                          response.get('idp_groups', []))))
        filtered_ad_groups = [g for g in ad_groups if not _group_matches_settings_exclude_patterns(g)]
        if len(filtered_ad_groups) == 0:
            log.warning('No groups were returned when authenticating user %s, before filter=%s, after filter=%s',
                        user.email, ad_groups, filtered_ad_groups)
            return

        for ag in user.groups.filter(name__iendswith='.DL'):
            user.groups.remove(ag)
            ag.user_set.remove(user)
        for ad_group in ad_groups:
            upper_ad_group = ad_group.upper()
            db_group, _ = Group.objects.get_or_create(name__iexact=upper_ad_group, defaults={'name': upper_ad_group})
            log.debug('Associating group=%s to user=%s', upper_ad_group, user.email)
            user.groups.add(db_group)
    else:
        log.warning('Skipping associating groups as user was not given.')


def _group_matches_settings_exclude_patterns(group_name: str) -> bool:
    if settings.SOCIAL_AUTH_GROUP_EXCLUDE_PATTERNS and isinstance(settings.SOCIAL_AUTH_GROUP_EXCLUDE_PATTERNS, list):
        for pattern in settings.SOCIAL_AUTH_GROUP_EXCLUDE_PATTERNS:
            if re.match(pattern, group_name):
                return True

    return False


def associate_by_email_or_username(backend, details, user=None, *args, **kwargs):
    """
    This is only safe because we're using MCRI's identity provider where accounts are maintained by MCRI IT
    and users cannot simply register themselves.  This means we can safely trust the email and username
    association coming from MCRI's identity provider.
    """
    if user:
        return None

    email = details.get('email')
    if email:
        users = User.objects.filter(Q(username__iexact=email) | Q(email__iexact=email))

        if len(users) == 0:
            return None
        elif len(users) > 1:
            raise AuthException(backend, 'The given email address is associated with another account')
        else:
            return {'user': users[0],
                    'is_new': False}


def log_authentication(backend, response, is_new=False, *args, **kwargs):
    log.info('Logged in {} ({})'.format(response['email'], backend.name))
    if is_new:
        log.info('Created user {} ({})'.format(response['email'], backend.name))
