import mock
from django.core.management import call_command
from django.test import TestCase
from parameterized import parameterized

from seqr.management.commands.create_training_projects import DEFAULT_PROJECT_CATEGORY


class CreateTrainingProjectsTest(TestCase):
    @parameterized.expand([
        ('project only', ['-p=template_001'], 'template_001', DEFAULT_PROJECT_CATEGORY, None, None, None, 1),
        ('project_category', ['-p', 'template_002', '-c=demo_training'], 'template_002', 'demo_training',
         None, None, None, 1),
        ('project_families', ['-p=template_002', '-f', 'FAM-SRR1301932', 'FAM-SRR1301936'], 'template_002',
         DEFAULT_PROJECT_CATEGORY, ['FAM-SRR1301932', 'FAM-SRR1301936'], None, None, 1),
        ('project_users', ['-p=template_002', '-u', 'lester.tester@mcri.edu.au', 'alice@mcri.edu.au'], 'template_002',
         DEFAULT_PROJECT_CATEGORY, None, ['lester.tester@mcri.edu.au', 'alice@mcri.edu.au'], None, 1),
        ('project_copies', ['-p=template_002', '-e', 'boss@mcri.edu.au', 'manager@mcri.edu.au'], 'template_002',
         DEFAULT_PROJECT_CATEGORY, None, None, ['boss@mcri.edu.au', 'manager@mcri.edu.au'], 1),
        ('project_copies', ['-p=template_002', '-n=5'], 'template_002',
         DEFAULT_PROJECT_CATEGORY, None, None, None, 5),
    ])
    @mock.patch('seqr.management.commands.create_training_projects.Command.create_projects')
    def test_command_args(self, _, given_args, exp_project, exp_category, exp_families, exp_collaborators,
                          exp_managers, exp_num_of_copy, mock_create_projects):
        call_command('create_training_projects', *given_args)
        mock_create_projects.assert_called_with(exp_project, exp_category, exp_families, exp_collaborators,
                                                exp_managers, exp_num_of_copy)
