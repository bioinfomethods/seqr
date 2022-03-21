import logging
from datetime import datetime

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.db import transaction

from seqr.models import Project, Family, Individual, ProjectCategory

logger = logging.getLogger(__name__)

PROTECTED_PROJECT_CATEGORIES = ['analyst-projects']
DEFAULT_TEMPLATE_PROJECT = 'R0029_test_project_grch38'
DEFAULT_PROJECT_CATEGORY = 'demo_{}'.format(datetime.now().strftime('%Y-%m-%d'))


class Command(BaseCommand):

    def add_arguments(self, parser):
        parser.add_argument('-p', '--template-project', nargs='?', const=DEFAULT_TEMPLATE_PROJECT,
                            default=DEFAULT_TEMPLATE_PROJECT, required=True,
                            help='Project as template for new projects, defaults to project guid={}'.format(
                                DEFAULT_TEMPLATE_PROJECT))
        parser.add_argument('-c', '--category', nargs='?', const=DEFAULT_PROJECT_CATEGORY,
                            default=DEFAULT_PROJECT_CATEGORY, required=False,
                            help='Seqr project category, defaults to {}'.format(DEFAULT_PROJECT_CATEGORY))
        parser.add_argument('-f', '--family-ids', nargs='*', required=False,
                            help='List of family IDs to include from template-project, defaults to all')
        parser.add_argument('-u', '--collaborators', nargs='*',
                            help='List of users to be given collaborator access to projects, defaults to none',
                            required=False)
        parser.add_argument('-e', '--managers', nargs='+',
                            help='List of users to be given manager access to projects, managers also get collaborator access, must provide at least one.',
                            required=True)
        parser.add_argument('-n', '--copies', nargs='?', const=1, default=1, type=int, required=False,
                            help='Number of copies of the template project to create')

    def handle(self, *args, **options):
        logger.info('options=%s', options)
        template_project = options['template_project']
        category = options['category']
        family_ids = options['family_ids']
        collaborators = options['collaborators']
        managers = options['managers']
        num_of_copies = options['copies']
        self.create_projects(template_project, category, family_ids, collaborators, managers, num_of_copies)

    @transaction.atomic
    def create_projects(self, template_project_guid, category, family_ids, collaborators, managers, num_of_copies):
        manager = User.objects.get(email=managers[0])
        if category in PROTECTED_PROJECT_CATEGORIES:
            raise RuntimeError('{} cannot be used by this script to create new projects'.format(category))

        project_category, _ = ProjectCategory.objects.get_or_create(name=category, defaults={'created_by': manager})

        new_project: Project = Project.objects.filter(guid__iexact=template_project_guid).first()

        logger.info(
            'Creating projects, template_project=%s, category=%s, family_ids=%s, collaborators=%s, managers=%s, num_of_copies=%s',
            template_project_guid, category, family_ids, collaborators, managers, num_of_copies)

        for copy_num in range(1, num_of_copies + 1):
            new_project.pk = None
            new_project.created_by = manager
            new_project.save()

            template_project: Project = Project.objects.get(guid__iexact=template_project_guid)

            new_project.name = '{}_{}'.format(template_project.name, str(copy_num).rjust(2, '0'))
            new_project.projectcategory_set.add(project_category)
            new_project.save()

            template_families = template_project.family_set.filter(family_id__in=family_ids) \
                if family_ids and len(family_ids) > 0 else template_project.family_set.all()
            if len(template_families) == 0:
                raise RuntimeError(
                    'Found no template families using given family_ids=%s.  Please use family ID (case sensitive) and not family guid'.format(
                        family_ids))

            for new_family in template_families:
                template_family_pk = new_family.pk
                new_family.pk = None
                new_family.project = new_project
                new_family.save()
                new_project.family_set.add(new_family)

                template_family: Family = Family.objects.get(pk=template_family_pk)

                # Keep a mapping of template to new ids of individuals so existing individuals from shared relationships are not duplicated
                individual_ids = {}

                for individual in template_family.individual_set.all():
                    template_individual_pk, new_individual_pk = self._get_or_create_individual_from_template(
                        individual_ids, new_family, individual)
                    individual_ids.update({template_individual_pk: new_individual_pk})

                    template_individual: Individual = Individual.objects.get(pk=template_individual_pk)
                    new_individual: Individual = Individual.objects.get(pk=new_individual_pk)

                    template_father: Individual = template_individual.father
                    if template_father:
                        template_father_pk, new_father_pk = self._get_or_create_individual_from_template(
                            individual_ids, new_family, template_father)
                        new_father = Individual.objects.get(pk=new_father_pk)
                        new_individual.father = new_father
                        new_individual.save()
                        individual_ids.update({template_father_pk: new_father_pk})

                    template_mother: Individual = template_individual.mother
                    if template_mother:
                        template_mother_pk, new_mother_pk = self._get_or_create_individual_from_template(
                            individual_ids, new_family, template_mother)
                        new_mother = Individual.objects.get(pk=new_mother_pk)
                        new_individual.mother = new_mother
                        new_individual.save()
                        individual_ids.update({template_mother_pk: new_mother_pk})

            can_view_users = (collaborators or []) + (managers or [])
            for user in User.objects.filter(email__in=can_view_users):
                logger.info('Assigning user=%s to project=%s as collaborator', user.email, new_project.guid)
                new_project.can_view_group.user_set.add(user)
            for user in User.objects.filter(email__in=managers or []):
                logger.info('Assigning user=%s to project=%s as manager', user.email, new_project.guid)
                new_project.can_edit_group.user_set.add(user)

            new_project.save()

    def _get_or_create_individual_from_template(self, individual_ids, family: Family, template: Individual):
        template_individual_pk = template.pk
        if template_individual_pk in individual_ids.keys():
            new_individual_pk = individual_ids.get(template_individual_pk)
        else:
            new_individual: Individual = template
            new_individual.pk = None
            new_individual.family = family
            new_individual.save()
            new_individual_pk = new_individual.pk
            logger.info('Created new_individual_pk=%s, family=%s, template_individual_pk=%s', new_individual_pk,
                        family.guid, template_individual_pk)

        template_individual: Individual = Individual.objects.get(pk=template_individual_pk)
        new_individual: Individual = Individual.objects.get(pk=new_individual_pk)
        for new_sample in template_individual.sample_set.all():
            new_sample.pk = None
            new_sample.individual = new_individual
            new_sample.save()

        return template_individual_pk, new_individual_pk
