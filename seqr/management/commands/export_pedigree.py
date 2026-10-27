from django.core.management.base import BaseCommand, CommandError
from collections import defaultdict
import sys

from seqr.models import Project, Individual, Sample


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
        parser.add_argument(
            '--dataset-type',
            default=Sample.DATASET_TYPE_VARIANT_CALLS,
            choices=[choice for choice, _ in Sample.DATASET_TYPE_CHOICES],
            help='Dataset type of the samples used to look up VCF IDs (default: SNV_INDEL)'
        )
        parser.add_argument(
            '--sample-type',
            choices=[choice for choice, _ in Sample.SAMPLE_TYPE_CHOICES],
            help='Sample type of the samples used to look up VCF IDs (default: any)'
        )

    def handle(self, *args, **options):
        project_guid = options['project_guid']
        output_path = options.get('output')
        family_guids = options.get('family_guids')
        dataset_type = options['dataset_type']
        sample_type = options.get('sample_type')

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

        vcf_ids = self._get_vcf_ids(individuals, dataset_type, sample_type)

        # Open output file or use stdout
        output_file = open(output_path, 'w') if output_path else sys.stdout

        try:
            # Write header
            output_file.write('Individual_ID\tFamily_GUID\tSex\tMaternal_ID\tPaternal_ID\tVCF_ID\n')

            # Write individual rows
            for individual in individuals:
                individual_id = individual.individual_id
                family_guid = individual.family.guid
                
                # Map sex to single letter format
                sex = self._format_sex(individual.sex)
                
                # Get parent IDs or use '.' for missing
                maternal_id = individual.mother.individual_id if individual.mother else '.'
                paternal_id = individual.father.individual_id if individual.father else '.'

                # Blank VCF_ID means the loading pipeline matches the VCF on Individual_ID
                vcf_id = vcf_ids.get(individual.id, '')
                if vcf_id == individual_id:
                    vcf_id = ''

                output_file.write(f'{individual_id}\t{family_guid}\t{sex}\t{maternal_id}\t{paternal_id}\t{vcf_id}\n')

            self.stderr.write(self.style.SUCCESS(
                f'Successfully exported {individuals.count()} individuals from project {project.name}'
            ))
            
            if output_path:
                self.stderr.write(self.style.SUCCESS(f'Output written to: {output_path}'))

        finally:
            if output_path:
                output_file.close()

    def _get_vcf_ids(self, individuals, dataset_type, sample_type):
        """Map individual pk -> sample ID as it appears in the VCF, from existing Sample records.

        Prefers active samples, then the most recently loaded.
        """
        samples = Sample.objects.filter(individual__in=individuals, dataset_type=dataset_type)
        if sample_type:
            samples = samples.filter(sample_type=sample_type)
        samples = samples.order_by('individual_id', '-is_active', '-loaded_date').values_list(
            'individual_id', 'individual__individual_id', 'sample_id')

        vcf_ids = {}
        all_sample_ids = defaultdict(set)
        for individual_pk, individual_id, sample_id in samples:
            vcf_ids.setdefault(individual_pk, sample_id)
            all_sample_ids[individual_id].add(sample_id)

        for individual_id, sample_ids in all_sample_ids.items():
            if len(sample_ids) > 1:
                self.stderr.write(self.style.WARNING(
                    f'Individual {individual_id} has multiple VCF IDs ({", ".join(sorted(sample_ids))}); '
                    f'using the active / most recently loaded one. Pass --sample-type to disambiguate'
                ))

        return vcf_ids

    def _format_sex(self, sex):
        """Convert seqr sex codes to single letter format (M/F/U)"""
        if sex == Individual.SEX_MALE:
            return 'M'
        elif sex == Individual.SEX_FEMALE:
            return 'F'
        else:
            return 'U'
