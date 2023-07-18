from typing import Dict, Any

import redis

from seqr.utils.logging_utils import SeqrLogger
from settings import REDIS_SERVICE_HOSTNAME, REDIS_SERVICE_PORT

logger = SeqrLogger(__name__)

BLANK_MCRI_POP_STAT_VARIANT = {
    'af': None,
    'filter_af': None,
    'ac': None,
    'an': None,
    'hom': None,
    'het': None,
    'id': None,
    'max_hl': None,
}


def filter_mcri_pop_stats(variants, user, search=None):
    logger.info(f"Attempting to apply and filter {len(variants)} variants with MCRI population stats", user)
    try:
        redis_client = redis.StrictRedis(host=REDIS_SERVICE_HOSTNAME, port=REDIS_SERVICE_PORT,
                                         socket_connect_timeout=5,
                                         decode_responses=True)
        redis_client.info()
    except Exception as e:
        logger.warning(
            'Unable to connect to redis host {}, returning variants unmodified: {}'.format(REDIS_SERVICE_HOSTNAME,
                                                                                           str(e)), user)
        return variants

    result = []

    def freq_filter(variant_stats: Dict):
        nonlocal search
        search_pop_mcri = search.get('freqs', {}).get('pop_mcri', {})
        search_ac = search_pop_mcri.get('ac')
        if search_ac:
            variant_ac = variant_stats.get('ac')
            if variant_ac and variant_ac > search_ac:
                return False
        search_af = search_pop_mcri.get('af')
        if search_af:
            variant_af = variant_stats.get('filter_af')
            if variant_af and variant_af > search_af:
                return False
        return True

    for variant in variants:
        annotated = _annotate_or_filter(redis_client, user, variant, freq_filter=freq_filter)
        logger.info(f"Annotated variant: {annotated.get('variantId') if annotated else None}", user)
        if annotated:
            result.append(annotated)

    return result


def _annotate_or_filter(redis_client, user, variant, freq_filter=None):
    """
    freq_filter is a closure (with variant variable already closed/curried) that takes population stats and returns
    True if variant passes filter.

    Given variant can have three possible outcomes:

    1. Returns variant with annotated population stats (in place mutation) if population stats exists and passes freq_filter
    2. Returns None if population stats exists and search filter is given but fails freq_filter
    3. Returns variant unmodified in all other cases including:
      - No redis_client
      - No population stats in redis or exception occurs during cache retrieval
    """
    if not redis_client or not variant:
        return variant

    cache_key = f"chr{variant.get('variantId')}"
    try:
        cache_value = redis_client.get(cache_key)
        if cache_value:
            logger.debug('Loaded {} from redis'.format(cache_key), user)
            v_pop_stats: Dict = _parse_key_values(cache_value, user)
            pop_mcri = BLANK_MCRI_POP_STAT_VARIANT.copy()
            ac = v_pop_stats.get('ac') or 0
            an = v_pop_stats.get('an') or 0
            af = 0 if (ac == 0 or an == 0) else (ac / an)
            pop_mcri.update(v_pop_stats)
            pop_mcri['af'] = af
            pop_mcri['filter_af'] = af

            if freq_filter:
                if freq_filter(pop_mcri):
                    logger.debug('Annotating variant {} with population stats {}'.format(cache_key, pop_mcri), user)
                    variant['populations']['pop_mcri'] = pop_mcri
                    return variant
                else:
                    logger.debug('Variant {} did not pass frequency filter'.format(cache_key), user)
                    return None
        else:
            logger.debug('Unable to fetch cache_value "{}" from redis'.format(cache_key), user)
    except ValueError as e:
        logger.debug('Unable to fetch "{}" from redis:\t{}'.format(cache_key, str(e)))

    return variant


def _parse_key_values(key_values_str: str, user) -> Dict[str, Any]:
    if not key_values_str:
        return {}
    key_values = key_values_str.split(';')
    result = {}
    for key_value_str in key_values:
        key_value = key_value_str.split('=')
        attr_name = key_value[0].lower()
        if len(key_value) == 2 and attr_name in ['ac', 'an'] and key_value[1].isnumeric():
            result[attr_name] = int(key_value[1])
        else:
            logger.debug(f'Unable to parse key-value pair: {key_value_str}', user)
    return result
