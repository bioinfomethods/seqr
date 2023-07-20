from seqr.utils.logging_utils import SeqrLogger
from seqr.views.utils.json_utils import create_json_response
from seqr.views.utils.orm_to_json_utils import get_json_for_current_user
from seqr.views.utils.permissions_utils import login_and_policies_required

logger = SeqrLogger(__name__)


@login_and_policies_required
def get_user(request):
    user_json = get_json_for_current_user(request.user)
    return create_json_response(user_json)
