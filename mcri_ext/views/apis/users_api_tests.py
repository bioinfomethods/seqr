from django.urls.base import reverse

from mcri_ext.views.apis.users_api import get_user
from seqr.views.utils.test_utils import AuthenticationTestCase


class UsersAPITest(AuthenticationTestCase):
    fixtures = ['users']

    def test_get_user(self):
        self.client.force_login(self.collaborator_user)
        url = reverse(get_user)
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        response_json = response.json()
        self.assertEqual(response_json['email'], 'test_user_collaborator@test.com')
