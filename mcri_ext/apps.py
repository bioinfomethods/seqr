import logging

from django.apps import AppConfig

log = logging.getLogger(__name__)

SEGMENT_SIZE = 500000
UPTO = 759302267


class McriExtConfig(AppConfig):
    name = 'mcri_ext'

    def ready(self):
        pass
