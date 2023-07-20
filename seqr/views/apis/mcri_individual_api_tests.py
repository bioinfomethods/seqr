# -*- coding: utf-8 -*-
import json

import mock
from django.urls.base import reverse

from seqr.views.apis.individual_api import load_individuals_from_staging
from seqr.views.utils.test_utils import AuthenticationTestCase

PROJECT_GUID = 'R0001_1kg'


@mock.patch('seqr.utils.middleware.DEBUG', False)
class McriIndividualAPITest(AuthenticationTestCase):
    fixtures = ['users', '1kg_project', 'reference_data']
    HAS_EXTERNAL_PROJECT_ACCESS = False

    def test_load_individuals_from_staging(self):
        load_individuals_url = reverse(load_individuals_from_staging, args=[PROJECT_GUID])
        self.check_manager_login(load_individuals_url)

        response = self.client.post(load_individuals_url, content_type='application/json',
                                    data=json.dumps({'pedigreePath': 'seqr/test_resources/pedigree.json'}))

        self.assertEqual(response.status_code, 200)
        response_json = response.json()
        self.assertEqual(set(response_json['familiesByGuid'].keys()), {'F000001_1'})
        self.assertEqual(set(response_json['individualsByGuid'].keys()), {'I000001_na19675'})
