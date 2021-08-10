from seqr.utils.logging_utils import SeqrLogger
from seqr.views.utils.json_utils import create_json_response
from seqr.views.utils.permissions_utils import superuser_required

logger = SeqrLogger(__name__)


@superuser_required
def echo(request):
    msg = request.POST.get('message', 'hello')
    name = request.POST.get('name', 'world')
    body = request.body
    logger.info('msg={}, name={}, body={}'.format(msg, name, body), request.user)

    return create_json_response({'from': 'EchoResource.POST', 'message': msg, 'name': name})
