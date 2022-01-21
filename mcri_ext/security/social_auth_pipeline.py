from django.contrib.auth.models import User, Group
from django.db.models import Q
from social_core.exceptions import AuthException

from seqr.utils.logging_utils import SeqrLogger

log = SeqrLogger(__name__)


def associate_groups(backend, response, user, details, *args, **kwargs):
    if user:
        log.info('Associating groups to user %s', user)
        user.groups.clear()
        idp_groups = [] if details.get('idp_groups', []) is None else details.get('idp_groups', [])
        if len(idp_groups) == 0:
            log.warning('No groups were returned when authenticating user %s', user.email)

        for idp_group in idp_groups:
            db_group, _ = Group.objects.get_or_create(name=idp_group)
            user.groups.add(db_group)
    else:
        log.warning('Skipping associating groups as user was not given.', None)


def associate_by_email_or_username(backend, details, user=None, *args, **kwargs):
    """
    This is only safe because we're using MCRI Okta where accounts are maintained by MCRI IT
    and users cannot simply register themselves.  This means we can safely trust the email and username
    association coming from MCRI Okta.
    """
    if user:
        return None

    email = details.get('email')
    if email:
        users = User.objects.filter(Q(username=email) | Q(email=email))

        if len(users) == 0:
            return None
        elif len(users) > 1:
            raise AuthException(
                backend,
                'The given email address is associated with another account'
            )
        else:
            return {'user': users[0],
                    'is_new': False}
