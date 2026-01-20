from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from seqr.models import Sample, Project
from seqr.views.utils.dataset_utils import match_and_update_search_samples
from seqr.utils.search.add_data_utils import basic_notify_search_data_loaded
from clickhouse_search.models import ENTRY_CLASS_MAP


class Command(BaseCommand):
    help = 'Register a ClickHouse dataset for a project by creating Sample records in PostgreSQL'

    def add_arguments(self, parser):
        parser.add_argument('project_guid', help='Project GUID')
        parser.add_argument('sample_type', choices=['WES', 'WGS'], help='Sample type (WES or WGS)')
        parser.add_argument('dataset_type', choices=['SNV_INDEL', 'SV', 'MITO'], help='Dataset type')
        parser.add_argument(
            '--ignore-extra-samples',
            action='store_true',
            help='Ignore samples in ClickHouse that do not match individuals in seqr'
        )
        parser.add_argument(
            '--mapping-file',
            help='Path to a file mapping sample IDs to individual IDs (two columns, tab-separated)'
        )

    def handle(self, *args, **options):
        project_guid = options['project_guid']
        sample_type = options['sample_type']
        dataset_type = options['dataset_type']
        ignore_extra_samples = options['ignore_extra_samples']
        mapping_file_path = options.get('mapping_file')

        # Get the project
        try:
            project = Project.objects.get(guid=project_guid)
        except Project.DoesNotExist:
            raise CommandError(f'Project with GUID "{project_guid}" does not exist')

        self.stdout.write(f'Registering {sample_type} {dataset_type} dataset for project: {project.name}')

        # Validate sample and dataset types
        if sample_type not in Sample.SAMPLE_TYPE_LOOKUP:
            raise CommandError(f'Invalid sample type: {sample_type}')

        if dataset_type not in Sample.DATASET_TYPE_LOOKUP:
            raise CommandError(f'Invalid dataset type: {dataset_type}')

        # Get the appropriate ClickHouse entry class
        entry_class = ENTRY_CLASS_MAP.get(project.genome_version, {}).get(dataset_type)
        if not entry_class:
            raise CommandError(
                f'No ClickHouse table found for {project.genome_version} {dataset_type}'
            )

        # Query ClickHouse for samples in this project
        self.stdout.write('Querying ClickHouse for samples...')
        
        # Use raw SQL since ClickHouse doesn't support joins on array fields
        from django.db import connections
        table_name = entry_class._meta.db_table
        
        with connections['clickhouse'].cursor() as cursor:
            # Escape table name with backticks since it contains forward slashes
            cursor.execute(f"""
                SELECT DISTINCT arrayJoin(calls.sampleId) as sample_id
                FROM `{table_name}`
                WHERE project_guid = %s
            """, [project_guid])
            sample_ids = [row[0] for row in cursor.fetchall()]

        if not sample_ids:
            raise CommandError('No samples found in ClickHouse for this project')

        self.stdout.write(f'Found {len(sample_ids)} samples in ClickHouse: {", ".join(sorted(sample_ids))}')

        # Load mapping file if provided
        sample_id_to_individual_id_mapping = {}
        if mapping_file_path:
            self.stdout.write(f'Loading mapping file: {mapping_file_path}')
            try:
                from seqr.views.utils.dataset_utils import load_mapping_file
                sample_id_to_individual_id_mapping = load_mapping_file(mapping_file_path, user=None)
                self.stdout.write(f'Loaded {len(sample_id_to_individual_id_mapping)} mappings')
            except Exception as e:
                raise CommandError(f'Error loading mapping file: {e}')

        # Prepare sample data
        sample_data = {}

        # Match and update samples
        sample_project_tuples = [(sample_id, project.name) for sample_id in sample_ids]

        try:
            new_samples, updated_samples, inactivated_sample_guids, updated_family_guids = match_and_update_search_samples(
                projects=[project],
                user=None,
                sample_project_tuples=sample_project_tuples,
                sample_data=sample_data,
                sample_type=sample_type,
                dataset_type=dataset_type,
                sample_id_to_individual_id_mapping=sample_id_to_individual_id_mapping,
                raise_unmatched_error_template=None if ignore_extra_samples else 'Matches not found for sample ids: {sample_ids}. Use --ignore-extra-samples to ignore unmatched samples.'
            )
        except ValueError as e:
            raise CommandError(str(e))

        # Report results
        self.stdout.write(self.style.SUCCESS(f'\nSuccessfully registered dataset:'))
        self.stdout.write(f'  New samples: {new_samples.count()}')
        self.stdout.write(f'  Updated samples: {updated_samples.count()}')
        self.stdout.write(f'  Inactivated samples: {len(inactivated_sample_guids)}')
        self.stdout.write(f'  Updated families: {len(updated_family_guids)}')

        if new_samples.exists():
            new_sample_ids = list(new_samples.values_list('sample_id', flat=True))
            self.stdout.write(f'\nNew sample IDs: {", ".join(sorted(new_sample_ids))}')

        # Send notification
        basic_notify_search_data_loaded(
            project, dataset_type, sample_type, new_samples.values_list('sample_id', flat=True)
        )

        self.stdout.write(self.style.SUCCESS('\nDataset registration complete!'))
