import logging

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Q

from seqr.models import ProjectCategory

logger = logging.getLogger(__name__)

PROTECTED_PROJECT_CATEGORIES = ['analyst-projects']


class Command(BaseCommand):

    def add_arguments(self, parser):
        parser.add_argument('-c', '--category', nargs='?', required=True,
                            help='Seqr project category name or guid to delete, if name is not unique then please use guid')

    def handle(self, *args, **options):
        category = options['category']
        self.delete_projects(category)

    @transaction.atomic
    def delete_projects(self, category):
        if category in PROTECTED_PROJECT_CATEGORIES:
            raise RuntimeError('{} cannot be deleted using this script'.format(category))

        deleteable_categories = [p.guid for p in
                                 ProjectCategory.objects.exclude(name__in=PROTECTED_PROJECT_CATEGORIES)]
        project_category = ProjectCategory.objects.filter(Q(guid=category) | Q(name=category)).first()
        if project_category is None:
            raise RuntimeError('project_category={} not found, deleteable project categories are {}'.format(category,
                                                                                                            deleteable_categories))

        for project in project_category.projects.all():
            for family in project.family_set.all():
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
            project.delete()

        project_category.delete()
