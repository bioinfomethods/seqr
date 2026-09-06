import logging

from django.core.management.base import BaseCommand, CommandError

from seqr.models import Project
from seqr.views.utils.individual_utils import add_or_update_individuals_and_families
from seqr.views.utils.pedigree_info_utils import parse_basic_pedigree_table

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = 'Add families and individuals to a project from a pedigree file (.fam or .tsv)'

    def add_arguments(self, parser):
        parser.add_argument('project_guid', help='Project GUID to add families to')
        parser.add_argument('pedigree_file', help='Path to a .fam or .tsv pedigree file')

    def handle(self, *args, **options):
        project_guid = options['project_guid']
        pedigree_file = options['pedigree_file']

        try:
            project = Project.objects.get(guid=project_guid)
        except Project.DoesNotExist:
            raise CommandError(f'Project with GUID "{project_guid}" does not exist')

        self.stdout.write(f'Loading pedigree from {pedigree_file} into project {project.name} ({project.guid})')

        try:
            with open(pedigree_file) as f:
                parsed_file = [
                    [field.strip() for field in line.rstrip('\n').split('\t')]
                    for line in f if line.strip()
                ]
        except FileNotFoundError:
            raise CommandError(f'Pedigree file not found: {pedigree_file}')

        if not parsed_file:
            raise CommandError('Pedigree file is empty')

        try:
            records = parse_basic_pedigree_table(project, parsed_file, pedigree_file)
        except Exception as e:
            raise CommandError(f'Error parsing pedigree file: {e}')

        self.stdout.write(f'Parsed {len(records)} individual records')

        try:
            result = add_or_update_individuals_and_families(
                project, records, user=None,
            )
        except Exception as e:
            raise CommandError(f'Error creating families/individuals: {e}')

        if result:
            families = result.get('familiesByGuid', {})
            individuals = result.get('individualsByGuid', {})
            self.stdout.write(self.style.SUCCESS(
                f'Successfully updated {len(families)} families and {len(individuals)} individuals'
            ))
            for guid, data in families.items():
                self.stdout.write(f'  Family: {guid} ({data.get("familyId", "")})')
            for guid, data in individuals.items():
                self.stdout.write(f'  Individual: {guid} ({data.get("individualId", "")})')
        else:
            self.stdout.write('No changes were made (records may already exist)')
