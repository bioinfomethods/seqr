import logging

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError
from django.db.models.query_utils import Q

from seqr.models import Family
from seqr.models import Project
from seqr.views.utils.pedigree_image_utils import update_pedigree_images

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = 'Admin script to bulk generate pedigree images for a given project'

    def add_arguments(self, parser):
        parser.add_argument('-u', '--username', help="Username", required=True)
        parser.add_argument('-p', '--project', help='Project to bulk generate pedigree images for', required=True)

    def handle(self, *args, **options):
        username = options.get('username')

        usernames = User.objects.filter(username=username)
        if len(usernames) == 0:
            raise CommandError("Username %s not found." % username)
        elif len(usernames) >= 2:
            raise CommandError("Username %s is duplicated." % username)
        user = usernames[0]

        project_name = options['project']
        project = Project.objects.get(Q(name=project_name) | Q(guid=project_name))
        families = Family.objects.filter(project=project)

        logger.info("Bulk generating pedigree images for project=%s, families=%s", project.guid,
                    ','.join([f.family_id for f in families]))
        update_pedigree_images(families, user, project_guid=project.guid)
