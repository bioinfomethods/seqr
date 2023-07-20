import json

from seqr.utils.file_utils import file_iter
from seqr.utils.logging_utils import SeqrLogger

logger = SeqrLogger(__name__)

from seqr.views.utils.individual_utils import add_or_update_individuals_and_families


def load_pedigree_to_project(project, pedigree_path, user):
    file_contents = '\n'.join(file_iter(pedigree_path, user=user))
    individual_records = json.loads(file_contents)
    pedigree_json = add_or_update_individuals_and_families(project, individual_records, user)
    logger.info(
        'Successfully loaded pedigree=%s into project=%s, pedigree_json=%s' % (pedigree_path, project.guid, pedigree_json), user)

    return pedigree_json
