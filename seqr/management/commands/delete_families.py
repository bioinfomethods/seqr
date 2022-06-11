import logging

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Q

from seqr.models import Project

logger = logging.getLogger(__name__)


class Command(BaseCommand):

    def add_arguments(self, parser):
        parser.add_argument('-p', '--project', nargs='?', required=True,
                            help='Project name or guid to filter families on')
        parser.add_argument('families', type=str, nargs='+',
                            help='List of family IDs to delete, use ID displayed in the UI')

    def handle(self, *args, **options):
        project = options['project']
        families = options['families']
        self.delete_families(project, families)

    @transaction.atomic
    def delete_families(self, project_ref, family_refs):
        for project in Project.objects.filter(Q(guid__iexact=project_ref) | Q(name__iexact=project_ref)):
            for family in project.family_set.filter(family_id__in=family_refs):
                logger.info('Deleting family=%s from project=%s', family.family_id, project.guid)
                family.savedvariant_set.all().delete()
                family.familyanalysedby_set.all().delete()
                family.analysisgroup_set.filter(project=project).delete()
                for individual in family.individual_set.all():
                    logger.info('Deleting individual=%s, family=%s, project=%s', project.guid, family.guid,
                                individual.guid)
                    individual.igvsample_set.all().delete()
                    if hasattr(individual, 'matchmakersubmission'):
                        individual.matchmakersubmission.delete()
                    individual.sample_set.all().delete()
                    individual.delete()
                family.delete()
