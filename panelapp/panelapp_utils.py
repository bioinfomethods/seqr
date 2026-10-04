import traceback
from collections import defaultdict

import requests
from django.db import transaction
from django.utils import timezone
from tenacity import retry, wait_exponential, stop_after_attempt, retry_if_exception_type
from urllib3.exceptions import MaxRetryError

from panelapp.models import PaLocusList, PaLocusListGene
from reference_data.models import GENOME_VERSION_GRCh38
from seqr.models import LocusList as SeqrLocusList, LocusListGene as SeqrLocusListGene
from seqr.utils.gene_utils import parse_locus_list_items
from seqr.utils.logging_utils import SeqrLogger
from seqr.views.utils.json_to_orm_utils import update_model_from_json, create_model_from_json

logger = SeqrLogger(__name__)

REQUEST_TIMEOUT_S = 300
GRCH38_BUILD_KEY = 'GRch38'

class TooManyRequestsError(Exception):
    pass

def _extract_ensembl_id_from_json(raw_gene_json):
    ensembl_genes_json = (raw_gene_json.get('gene_data') or {}).get('ensembl_genes')
    if not isinstance(ensembl_genes_json, dict):
        return None

    # PanelApp spells the build 'GRch38', but don't depend on that capitalisation
    releases = next(
        (v for k, v in ensembl_genes_json.items() if k.lower() == GRCH38_BUILD_KEY.lower()), None,
    )
    if not isinstance(releases, dict):
        return None

    # Coordinates are keyed by Ensembl release ('90', '115', ...) and PanelApp bumps that key when
    # it re-annotates, so take the newest release present rather than pinning a single version
    for release in sorted(releases.keys(), key=_ensembl_release_sort_key, reverse=True):
        ensembl_id = (releases.get(release) or {}).get('ensembl_id')
        if ensembl_id:
            return ensembl_id

    return None


def _ensembl_release_sort_key(release):
    # Numeric releases sort by value and ahead of any unparseable key
    try:
        return 1, int(release)
    except (TypeError, ValueError):
        return 0, 0


def import_all_panels(user, panel_app_api_url, label=None):
    panels_url = '{}/panels/?page=1'.format(panel_app_api_url)
    all_panels = _get_all_panels(panels_url, [])

    genes_by_panel_id = defaultdict(list)

    for panel in all_panels:
        panel_app_id = panel.get('id')
        logger.info('Importing panel id {}'.format(panel_app_id), user)
        try:
            with transaction.atomic():
                panel_genes_url = '{}/panels/{}/genes'.format(panel_app_api_url, panel_app_id)
                pa_locus_list = _create_or_update_locus_list_from_panel(user, panel_genes_url, panel, label)
                if not pa_locus_list:
                    logger.info('Panel id {} is up to date, skipping import'.format(panel_app_id), user)
                    continue

                if len(genes_by_panel_id[panel_app_id]) != panel['stats']['number_of_genes']:
                    _get_all_genes(panel_app_id, panel_genes_url, genes_by_panel_id)

                all_genes_for_panel = genes_by_panel_id[panel_app_id]
                if not all_genes_for_panel:
                    continue  # Genes in 'super panels' are associated with sub panels
                panel_genes_by_id = {}
                for gene in all_genes_for_panel:
                    ensembl_id = _extract_ensembl_id_from_json(gene)
                    if ensembl_id:
                        panel_genes_by_id[ensembl_id] = gene
                if not panel_genes_by_id:
                    logger.warning('No GRCh38 ensembl ids could be read from any of the {} genes in panel {}, '
                                   'skipping import'.format(len(all_genes_for_panel), panel_app_id), user)
                    continue

                raw_ensbl_38_gene_ids_csv = ','.join(panel_genes_by_id.keys())
                genes_by_id, _, invalid_items = parse_locus_list_items({'rawItems': raw_ensbl_38_gene_ids_csv}, genome_version=GENOME_VERSION_GRCh38)
                if len(invalid_items or []) > 0:
                    logger.warning('Genes found in panel {} but not in reference data, ignoring genes {}'
                                   .format(panel_app_id, invalid_items), user)
                _update_locus_list_genes_bulk(pa_locus_list, genes_by_id or {}, panel_genes_by_id, user)
        except Exception as e:
            logger.error('Error occurred when importing gene panel_app_id={}, error={}'.format(panel_app_id, e), user,
                         traceback=traceback.format_exc())


def delete_all_panels(user, panel_app_api_url):
    with transaction.atomic():
        to_delete_qs = SeqrLocusList.objects.filter(palocuslist__url__startswith=panel_app_api_url)
        SeqrLocusList.bulk_delete(user, queryset=to_delete_qs)


def _update_locus_list_genes_bulk(pa_locus_list, genes_by_id, panel_genes_by_id, user):
    seqr_locus_list = pa_locus_list.seqr_locus_list
    logger.info('Bulk updating genes for list {}'.format(seqr_locus_list), user)
    SeqrLocusList.bulk_delete(user, queryset=seqr_locus_list.locuslistgene_set.all())
    current_time = timezone.now()

    locuslistgenes = {
        gene_id: SeqrLocusListGene(
            locus_list=seqr_locus_list,
            gene_id=gene_id,
            created_by=user,
            created_date=current_time,
            guid='LL%05d_%s' % (seqr_locus_list.id, gene_id)
        ) for gene_id in genes_by_id.keys()
    }
    created_locuslistgenes = SeqrLocusListGene.objects.bulk_create(locuslistgenes.values(), batch_size=10000)
    created_locuslistgenes_by_id = {lg.gene_id: lg for lg in created_locuslistgenes}

    palocuslistgenes = {
        gene_id: _create_pa_locus_list_gene(created_locuslistgenes_by_id[gene_id], panel_genes_by_id[gene_id])
        for gene_id in genes_by_id.keys()
    }
    PaLocusListGene.objects.bulk_create(palocuslistgenes.values(), batch_size=10000)


def _create_pa_locus_list_gene(seqr_locus_list_gene, panel_gene_json):
    # Read only the fields we persist - 'panel' and 'gene_data' are intentionally not kept, but must
    # not be deleted either: _get_all_genes shares one gene dict between a super panel and its sub
    # panels, so mutating it here corrupts the gene for whichever panel is imported next
    result = PaLocusListGene(
        seqr_locus_list_gene=seqr_locus_list_gene,
        confidence_level=panel_gene_json.get('confidence_level'),
        biotype=panel_gene_json.get('biotype') or None,
        penetrance=panel_gene_json.get('penetrance') or None,
        mode_of_pathogenicity=panel_gene_json.get('mode_of_pathogenicity') or None,
        mode_of_inheritance=panel_gene_json.get('mode_of_inheritance') or None,
    )

    return result


def _get_all_panels(panels_url, all_results):
    resp = requests.get(panels_url, timeout=REQUEST_TIMEOUT_S)
    resp_json = resp.json()
    curr_page_results = [r for r in resp_json.get('results', []) if r.get('stats', {}).get('number_of_genes', 0) > 0]
    all_results += curr_page_results

    next_page = resp_json.get('next', None)
    if next_page is None:
        return all_results
    else:
        return _get_all_panels(next_page, all_results)


def _get_all_genes(panel_app_id: int, genes_url: str, results_by_panel_id: dict):
    @retry(
        retry=retry_if_exception_type((MaxRetryError, TooManyRequestsError)),
        wait=wait_exponential(multiplier=1, min=4, max=20),
        stop=stop_after_attempt(5),
    )
    def _get(url):
        resp = requests.get(url, timeout=REQUEST_TIMEOUT_S)
        if resp.status_code == 429:
            raise TooManyRequestsError()
        return resp.json()

    resp_json = _get(genes_url)
    for result in resp_json.get('results', []):
        panel_id = result.get('panel', {}).get('id')
        if panel_id:
            results_by_panel_id[panel_id].append(result)
        if panel_app_id != panel_id:
            results_by_panel_id[panel_app_id].append(result)

    next_page = resp_json.get('next', None)
    if next_page is None:
        return results_by_panel_id
    else:
        return _get_all_genes(panel_app_id, next_page, results_by_panel_id)


def _create_or_update_locus_list_from_panel(user, panelgenes_url, panel_json, label):
    panel_app_id = panel_json.get('id')
    pa_locus_list = _safe_get_locus_list(panelgenes_url)
    version = panel_json.get('version') or None
    if pa_locus_list and pa_locus_list.version == version:
        return None

    name = panel_json['name']
    disease_group = panel_json.get('disease_group') or None
    disease_sub_group = panel_json.get('disease_sub_group') or None
    status = panel_json.get('status') or None
    version_created = panel_json.get('version_created') or None
    description = _create_panel_description(panel_app_id, version, disease_group, disease_sub_group, label)
    new_seqrlocuslist_json = {
        'name': name,
        'description': description,
        'is_public': True,
    }
    new_palocuslist_json = {
        'disease_group': disease_group,
        'disease_sub_group': disease_sub_group,
        'status': status,
        'version': version,
        'version_created': version_created,
        'url': panelgenes_url,
    }
    if pa_locus_list:
        update_model_from_json(pa_locus_list.seqr_locus_list, new_seqrlocuslist_json, user)
    else:
        seqr_locus_list = create_model_from_json(SeqrLocusList, new_seqrlocuslist_json, user)
        pa_locus_list = PaLocusList.objects.create(seqr_locus_list=seqr_locus_list, panel_app_id=panel_app_id)

    update_model_from_json(pa_locus_list, new_palocuslist_json, user)

    return pa_locus_list


def _create_panel_description(panel_app_id, version, disease_group, disease_sub_group, label):
    disease_groups = [d for d in [disease_group, disease_sub_group] if d]

    return 'PanelApp_{label}{panel_app_id}_{version}{disease_groups}'.format(
        panel_app_id=panel_app_id,
        label='{}_'.format(label) if label else '',
        version=version,
        disease_groups='_{}'.format(';'.join(disease_groups)) if disease_groups else '',
    )


def _safe_get_locus_list(panelgenes_url):
    result = PaLocusList.objects.filter(url=panelgenes_url)

    return result.first() if result else None
