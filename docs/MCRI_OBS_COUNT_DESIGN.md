# MCRI Obs Count Feature Design

## Overview

The MCRI Obs Count feature extends the standard seqr variant frequency display to show allele counts
observed within MCRI's own internal WES (Whole Exome Sequencing) and WGS (Whole Genome Sequencing)
cohorts. These are displayed alongside public population databases (gnomAD, TOPMed, etc.) to help
analysts assess variant rarity within the MCRI-specific patient population.

The feature is gated by the Django setting `MCRI_SHOW_OBS_COUNTS` in `settings.py`. When `False`,
no MCRI population stats are injected into variant results.

---

## Comparison with Standard Population Frequencies

MCRI obs counts are implemented quite differently from the standard population frequency data
(gnomAD, TOPMed, ExAC, seqr, etc.).

### Standard populations (gnomAD, TOPMed, ExAC, seqr, etc.)

- Stored and indexed natively in **Elasticsearch** alongside the variant documents.
- Retrieved as part of the normal variant search query — the `populations` dict is populated by
  the search backend before the API layer ever sees the variants.
- Sorting by these populations (e.g. `gnomad`) is handled **natively by Elasticsearch**, so it
  works correctly across all pages of results.
- Frequency filtering is also applied **inside Elasticsearch** at query time.

### MCRI obs counts (`pop_mcri_wes`, `pop_mcri_wgs`)

- Stored separately in a **Redis** key-value cache, completely outside Elasticsearch.
- Retrieved **after** the search backend returns results, by a post-processing step in
  `_process_variants()` in the API layer.
- Sorting is done in **Python** on the already-retrieved page of results, not by the search
  backend — hence the warning shown to users when results span multiple pages.
- Frequency filtering is also applied in **Python** inside `filter_mcri_pop_stats()`, not at
  query time in Elasticsearch.

### Key limitations of the MCRI approach

Because MCRI counts are bolted on after the fact in Python, they have two significant limitations
compared to standard populations:

1. **Sort order is only correct within a single page** of results. When results span multiple
   pages, variants on later pages may have lower MCRI frequencies than those on the first page,
   meaning the analyst cannot rely on the sort order to surface the rarest variants.
2. **Frequency filtering may be incomplete** across multiple pages, since the filter is applied
   per-page in Python rather than at the source in Elasticsearch. Variants that would be excluded
   by an MCRI frequency threshold may still appear on subsequent pages.

These limitations are why the UI displays a prominent warning when MCRI sorting is active and
results span more than one page (see [Search Results Sort Warning](#search-results-sort-warning-uisharedcomponentspanelsearchvariantsearchresultsjsx) below).

---

## Back End: Storage

### Redis Cache (`mcri_deploy/docker/redis-cache-obs/`)

MCRI obs counts are pre-computed and stored in a **Redis** key-value cache, populated by the
`cache-obs.py` script.

#### Data Source

- Input: a gzipped VCF file containing obs count data (`AC`/`AN` fields in the `INFO` column).
- The VCF can be read from a local file path, a Google Cloud Storage (`gs://`) URL, or STDIN.

#### Key Format

Each variant is stored with a Redis key of the form:

```
{CHROM}-{POS}-{REF}-{ALT}-{ASSAY_TYPE}
```

where `ASSAY_TYPE` is either `WES` or `WGS`, and `CHROM` is taken directly from the VCF (e.g.
`chr1`). For example:

```
chr1-12345-A-T-WES
```

> **Note:** A bug was fixed in commit `7550a6f` where the lookup code was prepending an extra
> `chr` prefix, producing keys like `chrchr1-...`. The fix removed the duplicate prefix so the
> lookup key now matches the stored key exactly.

#### Value Format

The raw `INFO` string from the VCF is stored as the value. The relevant fields parsed from this
string are:

| Field | Description      |
|-------|------------------|
| `AC`  | Allele Count     |
| `AN`  | Allele Number    |

#### Caching Script (`cache-obs.py`)

- Reads the VCF line by line, parsing `CHROM`, `POS`, `REF`, `ALT`, and `INFO`.
- Constructs the Redis key as `{CHROM}-{POS}-{REF}-{ALT}-{ASSAY_TYPE}` and stores the raw `INFO`
  string as the value.
- Batches writes to Redis in segments of 500,000 variants at a time (`SEGMENT_SIZE = 500000`).
- Optionally flushes all existing Redis keys before loading (`--clear-redis` flag).
- Uses `tqdm` for progress display and logs batch throughput statistics.
- Accepts `--assay-type` argument which must be either `WES` or `WGS`; this suffix is appended to
  every key written in that run.

#### GCP Utility (`gcp_utils.py`)

- Provides `download_file(url)` to download a VCF from a GCS bucket to a local temp directory
  before processing.
- Caches the downloaded file locally to avoid re-downloading if the file already exists.

---

## Middle Tier: Supplying Data to the Front End

### `mcri_ext/utils/search/utils.py`

This module is responsible for reading MCRI obs counts from Redis and injecting them into variant
results returned by the search backend.

#### `filter_mcri_pop_stats(variants, user, search=None)`

Top-level entry point called from the API layer. It:

1. Establishes a Redis connection (with a 5-second connect timeout). If the connection fails,
   variants are returned unmodified with a warning logged.
2. Iterates over variants, handling both single variants and compound het pairs (lists of variants).
3. For each variant, calls `_annotate_or_filter()`.
4. Returns the (possibly filtered and annotated) list of variants.

#### `_annotate_or_filter(redis_client, user, variant, freq_filter=None)`

For a single variant:

1. Extracts `variantId` from the variant dict.
2. For each assay type (`WES`, `WGS`), constructs the Redis key as `{variantId}-{ASSAY_TYPE}` and
   attempts to fetch the cached `INFO` string.
3. If found, calls `_parse_key_values()` to extract `ac` and `an` as integers.
4. Computes `af = ac / an` (or `0.0` if either is zero).
5. Builds a population stats dict (based on `BLANK_MCRI_POP_STAT_VARIANT`) and injects it into
   `variant['populations']['pop_mcri_wes']` or `variant['populations']['pop_mcri_wgs']`.
6. If a `freq_filter` closure is provided and the variant fails the filter, returns `None`
   (causing the variant to be excluded from results).
7. Returns the annotated variant, or the original variant unmodified if no cache entry is found.

#### `freq_filter` closure (inside `filter_mcri_pop_stats`)

When a `search` dict is provided, a closure is constructed that checks the variant's `ac` and
`filter_af` against the search parameters under `search.freqs.pop_mcri_wes` /
`search.freqs.pop_mcri_wgs`. If the variant exceeds the requested AC or AF threshold, it is
filtered out.

#### `_parse_key_values(key_values_str, user)`

Parses the raw Redis value (a semicolon-delimited `INFO` string) into a dict. Only `AC` and `AN`
fields with numeric values are extracted; all other fields are ignored with a debug log.

#### Population Stats Dict Shape

```python
{
    'af': float,        # computed as ac/an
    'filter_af': float, # same as af (used for frequency filtering)
    'ac': int,          # allele count from Redis
    'an': int,          # allele number from Redis
    'hom': None,        # not available from obs VCF
    'het': None,        # not available from obs VCF
    'id': None,
    'max_hl': None,
}
```

### `seqr/views/apis/variant_search_api.py`

#### Feature Flag Check

At the top of `_process_variants()`:

```python
if MCRI_SHOW_OBS_COUNTS:
    variants = filter_mcri_pop_stats(variants, request.user, search=search)
    if sort and sort.startswith('pop_mcri'):
        variants.sort(key=comparator)
```

#### Sort Remapping in `query_variants_handler()`

If the requested sort key starts with `pop_mcri` (e.g. `pop_mcri_wes` or `pop_mcri_wgs`), the
sort passed to the Elasticsearch/search backend is remapped to `gnomad`:

```python
if sort.startswith('pop_mcri'):
    es_sort = 'gnomad'
else:
    es_sort = sort
```

This is because the search backend has no native knowledge of MCRI frequencies. The MCRI-based
sort is then applied in Python after the variants are retrieved and annotated.

#### Python-Side Sort

A comparator is defined:

```python
def comparator(v):
    if isinstance(v, list):
        v = v[0]
    return v.get('populations', {}).get(sort, {}).get('af', None) or 0
```

Variants are sorted ascending by MCRI AF. Compound het pairs are sorted by the AF of the first
variant in the pair.

---

## Front End: Display

### Population Field Names

Two MCRI population field keys are used throughout the front end stack:

| Field Key        | Description         |
|------------------|---------------------|
| `pop_mcri_wes`   | MCRI WES obs counts |
| `pop_mcri_wgs`   | MCRI WGS obs counts |

These are exported as named constants from `ui/shared/components/panel/search/constants.js`:

```js
export const MCRI_WES_CALLSET_FREQUENCY = 'pop_mcri_wes'
export const MCRI_WGS_CALLSET_FREQUENCY = 'pop_mcri_wgs'
```

Note that these constants are **not** included in the `SNP_FREQUENCIES` or `FREQUENCIES` arrays
(which drive the frequency filter UI), so MCRI frequencies do not appear as filterable frequency
fields in the search form. They are used only for display and sort purposes.

### Frequency Display (`ui/shared/components/panel/variants/Frequencies.jsx`)

The `POPULATIONS` array defines the ordered list of population frequency rows shown in the variant
frequency popup. MCRI populations are defined as:

```js
const MCRI_POP_WES = { field: 'pop_mcri_wes', fieldTitle: 'MCRI exomes', acDisplay: 'AC', showAcOnly: true }
const MCRI_POP_WGS = { field: 'pop_mcri_wgs', fieldTitle: 'MCRI genomes', acDisplay: 'AC' }
```

They appear **first** in the `POPULATIONS` array, before seqr, ExAC, gnomAD, and TOPMed.

#### Display Behaviour

| Population     | `showAcOnly` | `acDisplay` | Rendered output                        |
|----------------|-------------|-------------|----------------------------------------|
| MCRI exomes    | `true`      | `'AC'`      | `AC=<value>` only (no AF shown)        |
| MCRI genomes   | `false`     | `'AC'`      | AF value + `AC=<value> out of <AN>`    |

The `FreqSummary` component handles this logic: when `showAcOnly` is `true`, the AF `<b>` element
is suppressed and only the `acDisplay` count is rendered.

If `populations.pop_mcri_wes` or `populations.pop_mcri_wgs` is absent or has `af === null /
undefined`, the row is not rendered (returns `null`).

### Search Results Sort Warning (`ui/shared/components/panel/search/VariantSearchResults.jsx`)

When the following conditions are both true:

- `totalVariantsCount > recordsPerPage` (results span more than one page), **and**
- `variantSearchDisplay.sort.startsWith('POP_MCRI')`

...an error `<Message>` is displayed warning the analyst that MCRI frequency sorting is applied
per-page only (because it is performed in Python after retrieval, not natively in the search
backend). The message strongly recommends reducing results to a single page before relying on MCRI
frequency sort order to avoid overlooking relevant variants on subsequent pages.

---

## Data Flow Summary

```
Obs count VCF (WES or WGS, gzipped)
        │
        ▼
cache-obs.py
  Reads VCF line by line
  Key: {CHROM}-{POS}-{REF}-{ALT}-{WES|WGS}
  Value: raw INFO string (contains AC=N;AN=N;...)
        │
        ▼
Redis key-value store
        │
        ▼
mcri_ext/utils/search/utils.py :: filter_mcri_pop_stats()
  For each variant:
    - Looks up {variantId}-WES and {variantId}-WGS in Redis
    - Parses AC and AN from INFO string
    - Computes af = ac / an
    - Injects into variant['populations']['pop_mcri_wes'] / ['pop_mcri_wgs']
    - Optionally filters variant if AC/AF exceeds search thresholds
        │
        ▼
seqr/views/apis/variant_search_api.py :: _process_variants()
  - Calls filter_mcri_pop_stats() when MCRI_SHOW_OBS_COUNTS is True
  - Optionally sorts variants by pop_mcri_wes/wgs AF (ascending, Python-side)
  - Serialises enriched variants into JSON response as 'searchedVariants'
        │
        ▼
JSON response: searchedVariants[*].populations.pop_mcri_wes / pop_mcri_wgs
        │
        ▼
ui/shared/components/panel/variants/Frequencies.jsx
  POPULATIONS array: MCRI_POP_WES and MCRI_POP_WGS rendered first
  FreqSummary component:
    - MCRI exomes: shows AC only
    - MCRI genomes: shows AF and AC/AN
        │
        ▼
Analyst sees MCRI AC (and AF for WGS) alongside gnomAD/TOPMed frequencies
in the variant frequency popup
```

---

## Key Files

| File | Role |
|------|------|
| `mcri_deploy/docker/redis-cache-obs/cache-obs.py` | Populates Redis with obs counts from a gzipped VCF |
| `mcri_deploy/docker/redis-cache-obs/gcp_utils.py` | Downloads obs VCF from GCS to local temp dir |
| `mcri_ext/utils/search/utils.py` | Reads Redis, annotates variants with MCRI pop stats, applies freq filter |
| `seqr/views/apis/variant_search_api.py` | Calls MCRI enrichment; remaps sort key; applies Python-side MCRI sort |
| `ui/shared/components/panel/search/constants.js` | Exports `MCRI_WES_CALLSET_FREQUENCY` / `MCRI_WGS_CALLSET_FREQUENCY` constants |
| `ui/shared/components/panel/variants/Frequencies.jsx` | Renders MCRI frequency rows in variant frequency popup |
| `ui/shared/components/panel/search/VariantSearchResults.jsx` | Displays per-page sort warning when MCRI sort is active and results span multiple pages |
