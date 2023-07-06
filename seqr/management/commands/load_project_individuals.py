import json
import logging
import sys

from django.core.management.base import BaseCommand

from seqr.models import Project
from seqr.utils.file_utils import file_iter
from seqr.views.utils.individual_utils import add_or_update_individuals_and_families

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = """
    Admin script to load pedigree file into project, pedigree file must already exist in given path.  Assumes file in
    format:
[
    {
        "familyId": "fam01",
        "individualId": "fam01-01",
        "paternalId": "AA1149-02",
        "maternalId": "AA1149-03",
        "sex": "M",
        "affected": "A"
    },
    {
        "familyId": "fam01",
        "individualId": "fam01-02",
        "paternalId": "",
        "maternalId": "",
        "sex": "M",
        "affected": "N"
    },
    {
        "familyId": "fam01",
        "individualId": "fam01-03",
        "paternalId": "",
        "maternalId": "",
        "sex": "F",
        "affected": "N"
    }
]
    """

    def add_arguments(self, parser):
        parser.add_argument('-p', '--project', help='Project guid or name', required=True)
        parser.add_argument('-d', '--pedigree', help='Path to pedigree file, can be local or gs:// path',
                            required=True)

    def handle(self, *args, **options):
        given_project = options.get('project')
        pedigree_path = options.get('pedigree')

        project = Project.objects.get(guid__iexact=given_project)

        file_contents = '\n'.join(file_iter(pedigree_path, user=None))
        individual_records = json.loads(file_contents)

        try:
            pedigree_json = add_or_update_individuals_and_families(project, individual_records, None)
        except Exception as e:
            logger.error(str(e), exc_info=e)
            sys.exit(1)

        logger.info(
            'Successfuly loaded pedigree=%s into project=%s, pedigree_json=%s',
            pedigree_path, given_project, pedigree_json)
