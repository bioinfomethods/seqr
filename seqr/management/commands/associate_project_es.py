import logging
import sys

from django.core.management.base import BaseCommand
from django.db.models import Q
from django.utils import timezone

from seqr.models import Project
from seqr.views.utils import variant_utils
from seqr.views.utils.dataset_utils import match_and_update_samples, \
    validate_index_metadata_and_get_elasticsearch_index_samples, load_mapping_file

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

        try:
            sample_ids, sample_type = validate_index_metadata_and_get_elasticsearch_index_samples(
                index, project=project, dataset_type=DATASET_TYPE)
            logger.info('Validated index=%s, project=%s, sample_ids=%s, sample_type=%s', index, project.guid,
                        sample_ids, sample_type)
            if not sample_ids:
                raise ValueError('No samples found in the index. Make sure the specified caller type is correct')

            sample_id_to_individual_id_mapping = load_mapping_file(mapping_file_path,
                                                                   None) if mapping_file_path else {}
        except ValueError as e:
            logger.error(str(e), exc_info=e)
            sys.exit(1)

        data_source = 'archie'
        ignore_extra_samples = False
        try:
            samples, matched_individual_ids, activated_sample_guids, inactivated_sample_guids, updated_family_guids, remaining_sample_ids = match_and_update_samples(
                projects=[project],
                user=None,
                sample_ids=sample_ids,
                elasticsearch_index=index,
                sample_type=sample_type,
                data_source=data_source,
                dataset_type=DATASET_TYPE,
                sample_id_to_individual_id_mapping=sample_id_to_individual_id_mapping,
                raise_no_match_error=ignore_extra_samples,
                raise_unmatched_error_template=None if ignore_extra_samples else 'Matches not found for ES sample ids: {sample_ids}. Uploading a mapping file for these samples, or select the "Ignore extra samples in callset" checkbox to ignore.'
            )
        except ValueError as e:
            logger.error(str(e), exc_info=e)
            sys.exit(1)

        variant_utils.reset_cached_search_results(project)
        logger.info(
            'Successfully associated ES index=%s with project=%s.  samples=%s, matched_individual_ids=%s, activated_sample_guids=%s, inactivated_sample_guids=%s, updated_family_guids=%s, remaining_sample_ids=%s',
            index, project, [s.sample_id for s in samples], matched_individual_ids, activated_sample_guids,
            inactivated_sample_guids, updated_family_guids, remaining_sample_ids)
