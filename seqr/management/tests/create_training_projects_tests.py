import mock
from django.core.management import call_command
from django.test import TestCase
from parameterized import parameterized

from seqr.management.commands.create_training_projects import DEFAULT_PROJECT_CATEGORY
from seqr.models import Project, ProjectCategory, Family, Individual, Sample


class CreateTrainingProjectsTest(TestCase):
    fixtures = ['users', '1kg_project']

    @parameterized.expand([
        ('project only', ['-p=template_001', '-e', 'manager@mcri.edu.au'], 'template_001', DEFAULT_PROJECT_CATEGORY,
         None, None, ['manager@mcri.edu.au'], 1),
        ('project_category', ['-p', 'template_002', '-c=demo_training', '-e', 'manager@mcri.edu.au'], 'template_002',
         'demo_training',
         None, None, ['manager@mcri.edu.au'], 1),
        (
                'project_families',
                ['-p=template_002', '-f', 'FAM-SRR1301932', 'FAM-SRR1301936', '-e', 'manager@mcri.edu.au'],
                'template_002',
                DEFAULT_PROJECT_CATEGORY, ['FAM-SRR1301932', 'FAM-SRR1301936'], None, ['manager@mcri.edu.au'], 1),
        ('project_users',
         ['-p=template_002', '-u', 'lester.tester@mcri.edu.au', 'alice@mcri.edu.au', '-e', 'manager@mcri.edu.au'],
         'template_002',
         DEFAULT_PROJECT_CATEGORY, None, ['lester.tester@mcri.edu.au', 'alice@mcri.edu.au'], ['manager@mcri.edu.au'],
         1),
        ('project_copies', ['-p=template_002', '-e', 'manager@mcri.edu.au', 'boss@mcri.edu.au'], 'template_002',
         DEFAULT_PROJECT_CATEGORY, None, None, ['manager@mcri.edu.au', 'boss@mcri.edu.au'], 1),
        ('project_copies', ['-p=template_002', '-n=5', '-e', 'manager@mcri.edu.au'], 'template_002',
         DEFAULT_PROJECT_CATEGORY, None, None, ['manager@mcri.edu.au'], 5),
    ])
    @mock.patch('seqr.management.commands.create_training_projects.Command.create_projects')
    def test_command_args(self, _, given_args, exp_project, exp_category, exp_families, exp_collaborators,
                          exp_managers, exp_num_of_copy, mock_create_projects):
        call_command('create_training_projects', *given_args)
        mock_create_projects.assert_called_with(exp_project, exp_category, exp_families, exp_collaborators,
                                                exp_managers, exp_num_of_copy)

    def test_command(self):
        given_args_create = ['-p', 'R0001_1kg', '-c', 'demo_category', '-f', '1', '2', '-u',
                             'test_user_collaborator@test.com', '-e', 'test_user_manager@test.com', '-n', 2]

        call_command('create_training_projects', *given_args_create)

        actual_prj_cat = ProjectCategory.objects.get(name__exact='demo_category')
        self.assertEqual(actual_prj_cat.created_by.email, 'test_user_manager@test.com')

        actual_projects = actual_prj_cat.projects.all()
        for p in actual_projects:
            self.assertEqual(p.created_by.email, 'test_user_manager@test.com')
        self.assertSetEqual(set([p.name for p in actual_projects]),
                            {'1kg project nåme with uniçøde_01', '1kg project nåme with uniçøde_02'})
        actual_project_0: Project = actual_projects[0]
        self.assertSetEqual(set([u.email for u in actual_project_0.can_view_group.user_set.all()]),
                            {'test_user_collaborator@test.com', 'test_user_manager@test.com'})
        actual_project_1: Project = actual_projects[1]
        self.assertSetEqual(set([f.family_id for f in actual_project_0.family_set.all()]),
                            {'1', '2'})
        self.assertSetEqual(set([f.family_id for f in actual_project_1.family_set.all()]),
                            {'1', '2'})
        self.assertSetEqual(set([u.email for u in actual_project_1.can_edit_group.user_set.all()]),
                            {'test_user_manager@test.com'})

        actual_fam_0_0 = actual_project_0.family_set.all()[0]
        self.assertSetEqual(set([i.individual_id for i in actual_fam_0_0.individual_set.all()]),
                            {'NA19675_1', 'NA19679', 'NA19678'})
        actual_fam_0_1 = actual_project_0.family_set.all()[1]
        self.assertSetEqual(set([i.individual_id for i in actual_fam_0_1.individual_set.all()]),
                            {'HG00731', 'HG00732', 'HG00733'})
        actual_fam_1_0 = actual_project_1.family_set.all()[0]
        self.assertSetEqual(set([i.individual_id for i in actual_fam_1_0.individual_set.all()]),
                            {'NA19675_1', 'NA19679', 'NA19678'})
        actual_fam_1_1 = actual_project_1.family_set.all()[1]
        self.assertSetEqual(set([i.individual_id for i in actual_fam_1_1.individual_set.all()]),
                            {'HG00731', 'HG00732', 'HG00733'})

        ind_NA19675_1 = Individual.objects.get(family=actual_fam_0_0, individual_id='NA19675_1')
        ind_NA19679 = Individual.objects.get(family=actual_fam_0_0, individual_id='NA19679')
        ind_NA19678 = Individual.objects.get(family=actual_fam_0_0, individual_id='NA19678')
        self.assertEqual(ind_NA19675_1.father, ind_NA19678)
        self.assertEqual(ind_NA19675_1.mother, ind_NA19679)
        self.assertTrue(ind_NA19675_1.sample_set.count() > 0)
        self.assertTrue(ind_NA19679.sample_set.count() > 0)
        self.assertTrue(ind_NA19678.sample_set.count() > 0)

        ind_HG00731 = Individual.objects.get(family=actual_fam_1_1, individual_id='HG00731')
        ind_HG00732 = Individual.objects.get(family=actual_fam_1_1, individual_id='HG00732')
        ind_HG00733 = Individual.objects.get(family=actual_fam_1_1, individual_id='HG00733')
        self.assertEqual(ind_HG00731.father, ind_HG00732)
        self.assertEqual(ind_HG00731.mother, ind_HG00733)
        self.assertTrue(ind_HG00731.sample_set.count() > 0)
        self.assertTrue(ind_HG00732.sample_set.count() > 0)
        self.assertTrue(ind_HG00733.sample_set.count() > 0)

        # Execute delete script to undo above
        given_args_delete = ['-c', 'demo_category']

        call_command('delete_training_projects', *given_args_delete)

        self.assertFalse(ProjectCategory.objects.filter(name__exact='demo_category').exists())
        self.assertFalse(Project.objects.filter(
            name__in=['1kg project nåme with uniçøde_01', '1kg project nåme with uniçøde_02']).exists())
        self.assertFalse(Family.objects.filter(project__in=[actual_project_0.pk, actual_project_1.pk]).exists())
        self.assertFalse(Individual.objects.filter(
            family__in=[actual_fam_0_0.pk, actual_fam_0_1.pk, actual_fam_1_0.pk, actual_fam_1_1.pk]).exists())
        self.assertFalse(Sample.objects.filter(
            individual__in=[ind_NA19675_1.pk, ind_NA19679.pk, ind_NA19678.pk, ind_HG00731.pk, ind_HG00732.pk,
                            ind_HG00733.pk]).exists())

    def test_error_command_missing_template(self):
        with self.assertRaisesMessage(RuntimeError, 'Template project=not_exists_project_guid not found'):
            given_args_create = ['-p', 'not_exists_project_guid', '-c', 'demo_category', '-f', '1', '2', '-u',
                                 'test_user_collaborator@test.com', '-e', 'test_user_manager@test.com', '-n', 2]

            call_command('create_training_projects', *given_args_create)

    def test_error_command_no_families(self):
        with self.assertRaisesMessage(RuntimeError,
                                      "Found no template families using given family_ids=['none_fam1', 'none_fam2'].  Please use family ID (case sensitive) and not family guid"):
            given_args_create = ['-p', 'R0001_1kg', '-c', 'demo_category', '-f', 'none_fam1', 'none_fam2', '-u',
                                 'test_user_collaborator@test.com', '-e', 'test_user_manager@test.com', '-n', 2]

            call_command('create_training_projects', *given_args_create)

    def test_error_delete_protected_projects(self):
        with self.assertRaisesMessage(RuntimeError,
                                      "analyst-projects cannot be deleted using this script"):
            given_args_create = ['-p', 'R0001_1kg', '-c', 'demo_category', '-f', '1', '2', '-u',
                                 'test_user_collaborator@test.com', '-e', 'test_user_manager@test.com', '-n', 2]
            call_command('create_training_projects', *given_args_create)

            given_args_delete = ['-c', 'analyst-projects']
            call_command('delete_training_projects', *given_args_delete)

    def test_error_delete_project_category_not_exists(self):
        with self.assertRaisesRegex(RuntimeError,
                                    'project_category=not_exists_category not found, deleteable project categories are.*'):
            given_args_create = ['-p', 'R0001_1kg', '-c', 'demo_category', '-f', '1', '2', '-u',
                                 'test_user_collaborator@test.com', '-e', 'test_user_manager@test.com', '-n', 2]
            call_command('create_training_projects', *given_args_create)

            given_args_delete = ['-c', 'not_exists_category']
            call_command('delete_training_projects', *given_args_delete)
