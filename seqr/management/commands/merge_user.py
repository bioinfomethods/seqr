from django.core.management.base import BaseCommand, CommandError
from django.contrib.auth.models import User
from seqr.models import Family, FamilyAnalysedBy, IgvSample, Individual, Sample, LocusList, Project, VariantNote, VariantSearch, VariantSearchResults, VariantTag, VariantTagType, UserPolicy
from oauth2_provider.models import AccessToken

from social_django.models import UserSocialAuth
import logging
logger = logging.getLogger(__name__)
class Command(BaseCommand):

    def add_arguments(self, parser):
        parser.add_argument('-f', '--from-username', help="From username, this one will be removed", required=True)
        parser.add_argument('-t', '--to-username', help="To username, this one is kept", required=True)

    def handle(self, *args, **options):
        from_username = options.get('from_username')
        to_username = options.get('to_username')
        logger.info("Merging user %s into %s" % (from_username, to_username))

        from_user = User.objects.get(username=from_username)
        from_user_without_host = from_user.username.split('@')[0]
        to_user = User.objects.get(username=to_username)
        to_user_without_host = to_user.username.split('@')[0]
        if from_user_without_host != to_user_without_host:
            raise CommandError("From username %s and to username %s must be the same without host." % (from_username, to_username))

        Family.objects.filter(created_by=from_user).update(created_by=to_user)
        FamilyAnalysedBy.objects.filter(created_by=from_user).update(created_by=to_user)
        FamilyAnalysedBy.objects.filter(created_by=from_user).update(created_by=to_user)

        IgvSample.objects.filter(created_by=from_user).update(created_by=to_user)
        Individual.objects.filter(created_by=from_user).update(created_by=to_user)
        Sample.objects.filter(created_by=from_user).update(created_by=to_user)
        LocusList.objects.filter(created_by=from_user).update(created_by=to_user)
        Project.objects.filter(created_by=from_user).update(created_by=to_user)
        VariantNote.objects.filter(created_by=from_user).update(created_by=to_user)
        VariantSearch.objects.filter(created_by=from_user).update(created_by=to_user)
        VariantSearchResults.objects.filter(created_by=from_user).update(created_by=to_user)
        VariantTag.objects.filter(created_by=from_user).update(created_by=to_user)
        VariantTagType.objects.filter(created_by=from_user).update(created_by=to_user)
        UserPolicy.objects.filter(user=from_user).update(user=to_user)
        AccessToken.objects.filter(user=from_user).delete()
        AccessToken.objects.filter(user=to_user).delete()
        UserSocialAuth.objects.filter(user=from_user).update(user=to_user)

        from_user.groups.all().delete()
        for group in from_user.groups.all():
            if not to_user.groups.filter(name=group.name).exists():
                to_user.groups.add(group)
        from_user.groups.clear()
        from_user.delete()
        to_user.save()

        logger.info("Merged user %s into %s" % (from_username, to_username))
