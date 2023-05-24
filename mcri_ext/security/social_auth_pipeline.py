from seqr.utils.logging_utils import SeqrLogger

logger = SeqrLogger(__name__)
log = logger


def associate_groups(backend, response, user, details, *args, **kwargs):
    """
    Example on how to add groups from IDP as auth groups.
    """
    if user:
        logger.info('Associating groups to user {}'.format(user.email), user)
        # user.groups.clear()
        # for idp_group in details.get('idp_groups', []):
        #     db_group, _ = Group.objects.get_or_create(name=idp_group)
        #     user.groups.add(db_group)
    else:
        log.warning('Skipping associating groups as user was not given.')


def _group_matches_settings_exclude_patterns(group_name: str) -> bool:
    if hasattr(settings,
               'SOCIAL_AUTH_GROUP_EXCLUDE_PATTERNS') and settings.SOCIAL_AUTH_GROUP_EXCLUDE_PATTERNS and isinstance(
            settings.SOCIAL_AUTH_GROUP_EXCLUDE_PATTERNS, list):
        for pattern in settings.SOCIAL_AUTH_GROUP_EXCLUDE_PATTERNS:
            if re.match(pattern, group_name):
                return True

    return False


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
