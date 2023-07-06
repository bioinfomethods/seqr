import logging
import sys

from django.conf import settings
from django.core.management.base import BaseCommand
from django.db.models import Q

from seqr.models import Project
from seqr.utils.search.add_data_utils import add_new_search_samples

logger = logging.getLogger(__name__)

DATASET_TYPE = 'VARIANTS'


class Command(BaseCommand):
    help = 'Admin script to associate Elasticsearch index name with a given project'

    def add_arguments(self, parser):
        parser.add_argument('-e', '--index', help="Elasticsearch index name", required=True)
        parser.add_argument('-p', '--project', help='Project guid or name to associated index with', required=True)
        parser.add_argument('-m', '--mapping', help='ID mapping file path on Google Cloud', required=False)

    def handle(self, *args, **options):
        index = options.get('index')
        given_project = options.get('project')
        mapping_file_path = options.get('mapping')
        project = Project.objects.filter(Q(guid__iexact=given_project) | Q(name__iexact=given_project)).first()

        payload = {
            'datasetType': DATASET_TYPE,
            'elasticsearchIndex': index,
            'mappingFilePath': mapping_file_path,
        }
        url = f'{settings.BASE_URL}project/{project.guid}/project_page'
        summary_template = '{num_new_samples} new {sample_type}{dataset_type} samples are loaded in ' + url
        try:
            num_sample, inactivated_sample_guids, updated_family_guids, updated_samples, summary_message = add_new_search_samples(
                payload, project, None, summary_template=summary_template)
            logger.info(summary_message)
        except ValueError as e:
            logger.error(str(e), exc_info=e)
            sys.exit(1)
