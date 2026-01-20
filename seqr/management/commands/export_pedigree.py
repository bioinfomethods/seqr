from django.core.management.base import BaseCommand, CommandError
import sys

from seqr.models import Project, Individual


class Command(BaseCommand):
    help = 'Export pedigree file for a project in the format required by the loading pipeline'

    def add_arguments(self, parser):
        parser.add_argument('project_guid', help='Project GUID')
        parser.add_argument(
            '--output',
            help='Output file path (default: stdout)'
        )
        parser.add_argument(
            '--family-guids',
            help='Comma-separated list of family GUIDs to export (default: all families in project)'
        )

    def handle(self, *args, **options):
        project_guid = options['project_guid']
        output_path = options.get('output')
        family_guids = options.get('family_guids')

        # Get the project
        try:
            project = Project.objects.get(guid=project_guid)
        except Project.DoesNotExist:
            raise CommandError(f'Project with GUID "{project_guid}" does not exist')

        # Get individuals
        individuals = Individual.objects.filter(family__project=project).select_related('family')
        
        if family_guids:
            family_guid_list = [guid.strip() for guid in family_guids.split(',')]
            individuals = individuals.filter(family__guid__in=family_guid_list)

        if not individuals.exists():
            raise CommandError('No individuals found for the specified project/families')

        # Sort by family and individual ID for consistent output
        individuals = individuals.order_by('family__family_id', 'individual_id')

        # Open output file or use stdout
        output_file = open(output_path, 'w') if output_path else sys.stdout

        try:
            # Write header
            output_file.write('Individual_ID\tFamily_GUID\tSex\tMaternal_ID\tPaternal_ID\n')

            # Write individual rows
            for individual in individuals:
                individual_id = individual.individual_id
                family_guid = individual.family.guid
                
                # Map sex to single letter format
                sex = self._format_sex(individual.sex)
                
                # Get parent IDs or use '.' for missing
                maternal_id = individual.mother.individual_id if individual.mother else '.'
                paternal_id = individual.father.individual_id if individual.father else '.'
                
                output_file.write(f'{individual_id}\t{family_guid}\t{sex}\t{maternal_id}\t{paternal_id}\n')

            self.stderr.write(self.style.SUCCESS(
                f'Successfully exported {individuals.count()} individuals from project {project.name}'
            ))
            
            if output_path:
                self.stderr.write(self.style.SUCCESS(f'Output written to: {output_path}'))

        finally:
            if output_path:
                output_file.close()

    def _format_sex(self, sex):
        """Convert seqr sex codes to single letter format (M/F/U)"""
        if sex == Individual.SEX_MALE:
            return 'M'
        elif sex == Individual.SEX_FEMALE:
            return 'F'
        else:
            return 'U'
