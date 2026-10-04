"""Seed a freshly reset local deployment with the fixed state functional tests need.

Run by scripts/reset.sh after migrations complete. Safe to re-run: everything is
looked up before it is created, so a second invocation only reports what it found.

The user is matched on email because that is the only handle the OIDC login has to
work with. With Keycloak/Okta configured, SOCIAL_AUTH_PIPELINE runs
social_core.pipeline.social_auth.associate_by_email followed by validate_user_exist,
so an external identity signs in to a *pre-existing* Django account with the same
email, and is bounced back to /login if there is no such account. That makes seeding
the account here a prerequisite for logging in at all, not just a convenience.
"""

import os

from django.contrib.auth.models import Group, User
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from reference_data.models import GENOME_VERSION_CHOICES, GENOME_VERSION_GRCh38
from seqr.models import Project, UserPolicy
from settings import PM_USER_GROUP, SEQR_PRIVACY_VERSION, SEQR_TOS_VERSION

GENOME_VERSIONS = [choice[0] for choice in GENOME_VERSION_CHOICES]


class Command(BaseCommand):
    help = (
        'Seed a reset deployment with a superuser matching an external OIDC identity and '
        'a project, so functional tests start from a known state.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--email', required=True,
            help='Email of the external OIDC identity. Must match the address the identity '
                 'provider asserts, or the login pipeline will not associate the two.',
        )
        parser.add_argument('--first-name', default='', help='Optional first name for the seeded user.')
        parser.add_argument('--last-name', default='', help='Optional last name for the seeded user.')
        parser.add_argument('--project', default='Test Project', help='Name of the project to seed.')
        parser.add_argument(
            '--genome-version', default=GENOME_VERSION_GRCh38, choices=GENOME_VERSIONS,
            help='Genome version for the seeded project.',
        )
        parser.add_argument(
            '--skip-project', action='store_true',
            help='Seed only the user, leaving the project list untouched.',
        )

    @transaction.atomic
    def handle(self, *args, **options):
        email = options['email'].strip().lower()
        if not email:
            raise CommandError('--email must not be blank')

        user = self._seed_user(email, options['first_name'], options['last_name'])
        self._accept_policies(user)
        self._grant_pm(user)

        if options['skip_project']:
            self.stdout.write('Skipping project creation (--skip-project).')
        else:
            self._seed_project(user, options['project'], options['genome_version'])

        self._warn_about_oidc_group_reset()

    def _seed_user(self, email, first_name, last_name):
        user = User.objects.filter(email__iexact=email).first()
        if user:
            self.stdout.write(f'Found existing user {user.email}')
        else:
            user = User.objects.create_user(
                username=email, email=email, first_name=first_name, last_name=last_name,
            )
            # Authentication happens through the identity provider, so there is no local
            # password to set. An unusable one keeps the account from being brute forced
            # via any password-based path that stays enabled.
            user.set_unusable_password()
            self.stdout.write(self.style.SUCCESS(f'Created user {user.email}'))

        user.is_staff = True
        user.is_superuser = True
        user.save()
        self.stdout.write('  is_staff and is_superuser set')
        return user

    def _accept_policies(self, user):
        """Pre-accept the privacy policy and terms of service.

        Without this, every view behind login_and_policies_required redirects to the
        acceptance page, so a functional test would have to click through it on each
        reset before it could reach anything worth asserting on.
        """
        policy, created = UserPolicy.objects.update_or_create(
            user=user,
            defaults={'privacy_version': SEQR_PRIVACY_VERSION, 'tos_version': SEQR_TOS_VERSION},
        )
        verb = 'Accepted' if created else 'Refreshed'
        self.stdout.write(
            f'  {verb} policies (privacy {policy.privacy_version}, tos {policy.tos_version})'
        )

    def _grant_pm(self, user):
        """Make the user a project manager, which gates project creation in the UI.

        permissions_utils.user_is_pm falls back to is_superuser only when PM_USER_GROUP
        is empty. docker-compose.yml defaults it to 'project-managers', so the superuser
        flag alone leaves the Create Project button hidden and the API returning 403.
        """
        if not PM_USER_GROUP:
            self.stdout.write('  PM_USER_GROUP is unset; superuser flag alone grants PM access')
            return

        group, _ = Group.objects.get_or_create(name=PM_USER_GROUP)
        user.groups.add(group)
        self.stdout.write(f'  Added to PM group "{PM_USER_GROUP}"')

    def _seed_project(self, user, name, genome_version):
        project = Project.objects.filter(name=name).first()
        if project:
            self.stdout.write(f'Found existing project {project.guid} ("{project.name}")')
        else:
            # created_by is not optional: Project.save() reads it to build the project's
            # permission groups and add the creator to them.
            project = Project.objects.create(
                name=name,
                description='Seeded by bootstrap_dev_data for local development and functional tests',
                genome_version=genome_version,
                created_by=user,
            )
            self.stdout.write(self.style.SUCCESS(f'Created project {project.guid} ("{project.name}")'))

        # A pre-existing project may have been created by a different account, in which
        # case this user holds no permission on it and it would not appear on their
        # dashboard. Adding them to the edit group makes the seeded state uniform either way.
        if project.can_edit_group and not user.groups.filter(pk=project.can_edit_group.pk).exists():
            user.groups.add(project.can_edit_group)
            self.stdout.write('  Granted edit access to the seeded user')

        self.stdout.write(
            f'  Project GUID {project.guid}, genome version {project.get_genome_version_display()}'
        )

    def _warn_about_oidc_group_reset(self):
        """Flag the one way the seeded PM grant silently disappears.

        mcri_ext.security.social_auth_pipeline.associate_groups calls user.groups.clear()
        on every OIDC login and re-adds only the groups asserted in the token, so an
        identity provider that returns any groups at all drops both the PM grant and the
        per-project permission groups seeded here.
        """
        if not PM_USER_GROUP:
            return
        if not os.environ.get('SOCIAL_AUTH_PROVIDER'):
            return
        self.stdout.write(self.style.WARNING(
            f'\nNote: signing in through OIDC replaces this user\'s groups with the ones the '
            f'identity provider asserts. If it does not assert "{PM_USER_GROUP}", the project '
            f'manager grant and project access seeded here are dropped on first login. Use the '
            f'test login (ENABLE_TEST_LOGIN) for functional tests, or have the provider assert '
            f'a group and point PM_USER_GROUP at it.'
        ))
