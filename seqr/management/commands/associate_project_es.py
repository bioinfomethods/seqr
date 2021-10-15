import logging

from django.core.management.base import BaseCommand
from django.utils import timezone

from seqr.models import Project
from seqr.models import Sample, Family
from seqr.views.utils import variant_utils
from seqr.views.utils.dataset_utils import match_sample_ids_to_sample_records, update_variant_samples, \
    validate_index_metadata_and_get_elasticsearch_index_samples, load_mapping_file
from seqr.views.utils.json_utils import create_json_response

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
        if given_project.upper().startswith('R00'):
            project = Project.objects.get(guid__iexact=given_project)
        else:
            project = Project.objects.get(name__iexact=given_project)

        try:
            sample_ids, sample_type = validate_index_metadata_and_get_elasticsearch_index_samples(
                index, project=project, dataset_type=DATASET_TYPE)
            if not sample_ids:
                raise ValueError('No samples found in the index. Make sure the specified caller type is correct')

            sample_id_to_individual_id_mapping = load_mapping_file(mapping_file_path,
                                                                   None) if mapping_file_path else {}
        except ValueError as e:
            return create_json_response({'errors': [str(e)]}, status=400)

        loaded_date = timezone.now()
        ignore_extra_samples = True
        try:
            samples, included_families, matched_individual_ids = match_sample_ids_to_sample_records(
                project=project,
                user=None,
                sample_ids=sample_ids,
                elasticsearch_index=index,
                sample_type=sample_type,
                dataset_type=DATASET_TYPE,
                sample_id_to_individual_id_mapping=sample_id_to_individual_id_mapping,
                loaded_date=loaded_date,
                raise_no_match_error=ignore_extra_samples,
                raise_unmatched_error_template=None if ignore_extra_samples else 'Matches not found for ES sample ids: {sample_ids}. Uploading a mapping file for these samples, or select the "Ignore extra samples in callset" checkbox to ignore.'
            )
        except ValueError as e:
            return create_json_response({'errors': [str(e)]}, status=400)

        activated_sample_guids, inactivated_sample_guids = update_variant_samples(
            samples, None, index, loaded_date, DATASET_TYPE, sample_type)
        updated_samples = Sample.objects.filter(guid__in=activated_sample_guids)

        family_guids_to_update = [
            family.guid for family in included_families if
            family.analysis_status == Family.ANALYSIS_STATUS_WAITING_FOR_DATA
        ]

        Family.bulk_update(
            None, {'analysis_status': Family.ANALYSIS_STATUS_ANALYSIS_IN_PROGRESS},
            guid__in=family_guids_to_update)

        variant_utils.reset_cached_search_results(project)
        logger.info('Successfully associated ES index=%s with project=%s and %d samples were updated',
                    index, project, updated_samples.count())
