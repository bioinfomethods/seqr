import logging
import os
import tempfile
import time

from google.api_core.exceptions import Forbidden
from google.cloud import storage

logger = logging.getLogger(__name__)


def download_file(url, to_dir=tempfile.gettempdir()):
    """Download the given file and returns its local path.
     Args:
        url (string): must start with gs://
     Returns:
        string: local file path
    """

    if not (url and url.startswith("gs://")):
        raise ValueError("Invalid url: {}".format(url))
    local_file_path = os.path.join(to_dir, os.path.basename(url))

    if os.path.exists(local_file_path):
        logger.info("File already exists: {}".format(local_file_path))
        return local_file_path

    logger.info("Downloading {} to {}".format(url, local_file_path))
    start_time = time.time()
    try:
        storage_client = storage.Client()
        bucket_name, blob_name = url[5:].split("/", 1)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        blob.download_to_filename(local_file_path)
    except Forbidden:
        logger.info("Forbidden: {}".format(url))
        raise
    except Exception as e:
        logger.info("Error downloading {}: {}".format(url, e))
        raise
    logger.info("Downloaded {} in {:.2f} seconds".format(url, time.time() - start_time))

    return local_file_path
