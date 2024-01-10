"""Usage: cache-obs.py [options]

Caches given obs count VCF into Redis

Options:
   -h --help                            show this help message and exit
   -r, --host=<str> REDIS_HOST          Redis host name [default: redis]
   -p, --port=<int> REDIS_PORT          Redis host port [default: 6379]
   -f, --vcf=<str>  OBS_COUNT_VCF_PATH  Obs count VCF gzipped [default: STDIN]
   -t, --assay-type=<str> ASSAY_TYPE    Assay type, must be either WES or WGS
   -c, --clear-redis                    Clear all keys from Redis before caching
"""

import gzip
import logging
import sys
from time import perf_counter
from typing import Dict, Any

import tqdm
from docopt import docopt
from redis import Redis
from tqdm import tqdm

from gcp_utils import download_file

logging.basicConfig(level=logging.INFO, format='{asctime} {levelname} [{name}] - {message}', style='{')
log = logging.getLogger(__name__)

SEGMENT_SIZE = 500000


def _parse_info_fields(info_str: str) -> Dict[str, Any]:
    if not info_str:
        return {}
    key_values = info_str.split(';')
    result = {}
    for key_value_str in key_values:
        key_value = key_value_str.split('=')
        if len(key_value) == 2 and key_value[0] in ['AC', 'AN'] and key_value[1].isnumeric():
            result[key_value[0]] = int(key_value[1])
        else:
            log.warning(f'Unable to parse key-value pair: {key_value_str}')
    return result


def cache_obs(args):
    filearg = args['--vcf']
    if filearg != 'STDIN':
        if filearg.startswith('gs://'):
            filepath = download_file(filearg)
        else:
            filepath = filearg

        obs_vcf = filepath
        log.info(f'Using {obs_vcf} as input')
    else:
        obs_vcf = sys.stdin.buffer
        log.info('Using STDIN as input')

    assay_type = args['--assay-type']
    if assay_type not in ['WES', 'WGS']:
        raise ValueError("Invalid value for --assay-type. It must be either 'WES' or 'WGS'.")

    redis_client = Redis(host=args['--host'], port=args['--port'], decode_responses=True)
    start = perf_counter()
    batch_start = perf_counter()
    elapsed = 0
    batch_data: Dict[str, str] = {}

    if args['--clear-redis']:
        log.info('Removing all keys from Redis')
        redis_client.flushall()

    with gzip.open(obs_vcf, mode='rt') as f:
        for line_num, line in enumerate(tqdm(f)):
            if line.startswith('##'):
                continue
            chr, pos, id, ref, alt, qual, filter, info, *rest = line.split('\t')
            variant_id = f'{chr}-{pos}-{ref}-{alt}-{assay_type}'
            batch_data[variant_id] = info

            if line_num % SEGMENT_SIZE == 0:
                redis_client.mset(batch_data)
                batch_data: Dict[str, str] = {}
                batch_stop = perf_counter()
                batch_total = batch_stop - batch_start
                elapsed += batch_total

                log.info(
                    f'Wrote {line_num} variants, batch rate: {int(SEGMENT_SIZE // batch_total)} var/s, batch duration: {int(batch_total)} secs, elapsed: {int(elapsed)} secs')
                batch_start = perf_counter()

    stop = perf_counter()
    log.info(f'Wrote {line_num} variants in {int(stop - start)} secs')


if __name__ == '__main__':
    arguments = docopt(__doc__)

    cache_obs(arguments)
