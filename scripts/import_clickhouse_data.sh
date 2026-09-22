#!/bin/bash
# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Required Options:
    --run-id RUN_ID             Run ID for the pipeline data
    --project-guid GUID          Project GUID
    --sample-type TYPE           Sample type (WES or WGS)
    --family-guids GUIDS         Comma-separated family GUIDs (at least one required)

Optional Options:
    --reference-genome GENOME    Reference genome (default: GRCh38)
    --dataset-type TYPE          Dataset type (default: SNV_INDEL)
    --remote-host HOST           Remote host to copy data from (e.g., mk4)
    --remote-path PATH           Remote base path for pipeline data
    --pipelines-dir DIR          Local seqr-loading-pipelines directory
    --seqr-dir DIR              Local seqr directory
    --pipelines-uv-env ENV       UV environment name for loading pipelines
    --seqr-uv-env ENV           UV environment name for seqr
    --skip-load                  Skip the load_to_clickhouse.py step
    --skip-copy                  Skip the remote copy step
    --skip-register              Skip the register_clickhouse_dataset step
    -h, --help                   Show this help message

Example:
    $0 --run-id 20260120-183723-474796 \\
       --project-guid R0133_testclickhouse \\
       --sample-type WGS \\
       --family-guids F003848_f0002

EOF
    exit 1
}

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# The loading pipelines are a separate repo. Prefer the checkout inside this working tree
# (./seqr-loading-pipelines), falling back to the older sibling-directory location for
# hosts that still keep it outside the repo. Override with --pipelines-dir or $PIPELINES_DIR.
#
# Written as an if/elif rather than a `cd A && pwd || cd B && pwd` chain: in that form the
# trailing `&& pwd` still runs after a successful first branch (the `||` only skips the `cd`,
# it does not short-circuit the rest of the list), so the path gets printed twice.
default_pipelines_dir() {
    if [ -d "$BASE_DIR/seqr-loading-pipelines" ]; then
        (cd "$BASE_DIR/seqr-loading-pipelines" && pwd)
    elif [ -d "$BASE_DIR/../seqr-loading-pipelines-clickhouse" ]; then
        (cd "$BASE_DIR/../seqr-loading-pipelines-clickhouse" && pwd)
    fi
}
PIPELINES_DIR="${PIPELINES_DIR:-$(default_pipelines_dir)}"
SEQR_DIR="${SEQR_DIR:-$BASE_DIR}"
PIPELINES_UV_ENV="${PIPELINES_UV_ENV:-seqr-loading-pipelines}"
SEQR_UV_ENV="${SEQR_UV_ENV:-seqr}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_PATH="${REMOTE_PATH:-/misc/bioinf-ops/seqr-clickhouse-ingest/pipeline-data}"
SKIP_LOAD=false
SKIP_COPY=false
SKIP_REGISTER=false

# Default optional parameters
REFERENCE_GENOME="GRCh38"
DATASET_TYPE="SNV_INDEL"

# Required parameters
RUN_ID=""
PROJECT_GUID=""
SAMPLE_TYPE=""
FAMILY_GUIDS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --reference-genome)
            REFERENCE_GENOME="$2"
            shift 2
            ;;
        --dataset-type)
            DATASET_TYPE="$2"
            shift 2
            ;;
        --run-id)
            RUN_ID="$2"
            shift 2
            ;;
        --project-guid)
            PROJECT_GUID="$2"
            shift 2
            ;;
        --sample-type)
            SAMPLE_TYPE="$2"
            shift 2
            ;;
        --family-guids)
            FAMILY_GUIDS="$2"
            shift 2
            ;;
        --remote-host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --remote-path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        --pipelines-dir)
            PIPELINES_DIR="$2"
            shift 2
            ;;
        --seqr-dir)
            SEQR_DIR="$2"
            shift 2
            ;;
        --pipelines-uv-env)
            PIPELINES_UV_ENV="$2"
            shift 2
            ;;
        --seqr-uv-env)
            SEQR_UV_ENV="$2"
            shift 2
            ;;
        --skip-load)
            SKIP_LOAD=true
            shift
            ;;
        --skip-copy)
            SKIP_COPY=true
            shift
            ;;
        --skip-register)
            SKIP_REGISTER=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RUN_ID" || -z "$PROJECT_GUID" || -z "$SAMPLE_TYPE" || -z "$FAMILY_GUIDS" ]]; then
    echo "Error: Missing required parameters"
    echo "Required: --run-id, --project-guid, --sample-type, --family-guids"
    usage
fi

# Validate reference genome
if [[ "$REFERENCE_GENOME" != "GRCh37" && "$REFERENCE_GENOME" != "GRCh38" ]]; then
    echo "Error: Reference genome must be GRCh37 or GRCh38"
    exit 1
fi

# Validate dataset type
if [[ "$DATASET_TYPE" != "SNV_INDEL" && "$DATASET_TYPE" != "SV" && "$DATASET_TYPE" != "MITO" ]]; then
    echo "Error: Dataset type must be SNV_INDEL, SV, or MITO"
    exit 1
fi

# Validate sample type
if [[ "$SAMPLE_TYPE" != "WES" && "$SAMPLE_TYPE" != "WGS" ]]; then
    echo "Error: Sample type must be WES or WGS"
    exit 1
fi

echo "=========================================="
echo "ClickHouse Data Import"
echo "=========================================="
echo "Reference Genome: $REFERENCE_GENOME"
echo "Dataset Type: $DATASET_TYPE"
echo "Run ID: $RUN_ID"
echo "Project GUID: $PROJECT_GUID"
echo "Sample Type: $SAMPLE_TYPE"
echo "Family GUIDs: $FAMILY_GUIDS"
echo "=========================================="

source  $HOME/work/tools/uv/environments/$PIPELINES_UV_ENV/bin/activate

# step 1: Copy data from remote host (if not skipped and remote host specified)
if [[ "$SKIP_COPY" == false && -n "$REMOTE_HOST" ]]; then
    echo ""
    echo "Step 1: Copying data from remote host..."
    
    REMOTE_RUN_PATH="$REMOTE_PATH/$REFERENCE_GENOME/$DATASET_TYPE/runs/$RUN_ID"
    # Mirror the remote layout exactly. ClickHouse resolves run parquet as
    #   file('$CLICKHOUSE_DATA_DIR/<genome>/<dataset_type>/runs/<run_id>/*.parquet')
    # and CLICKHOUSE_DATA_DIR is the container's view of data/clickhouse-seqr-data/pipeline-data
    # (see the bind mount on the clickhouse service). Copying into a flat data/runs only ever
    # worked because a second mount pinned that directory onto the SNV_INDEL run path; once a
    # non-SNV_INDEL dataset type was loaded it resolved to an unmounted path and found nothing.
    LOCAL_RUN_PATH="$SEQR_DIR/data/clickhouse-seqr-data/pipeline-data/$REFERENCE_GENOME/$DATASET_TYPE/runs"

    mkdir -p "$LOCAL_RUN_PATH"
    
    echo "Copying from $REMOTE_HOST:$REMOTE_RUN_PATH to $LOCAL_RUN_PATH"
    scp -r "$REMOTE_HOST:$REMOTE_RUN_PATH" "$LOCAL_RUN_PATH/"
    
    echo "✓ Data copied from remote host"
elif [[ "$SKIP_COPY" == false ]]; then
    echo "Step 1: Skipped (no remote host specified)"
else
    echo "Step 1: Skipped (--skip-copy)"
fi


# Step 2: Load to ClickHouse (if not skipped)
if [[ "$SKIP_LOAD" == false ]]; then
    echo ""
    echo "Step 2: Loading data to ClickHouse..."
    
    if [[ -z "$PIPELINES_DIR" || ! -d "$PIPELINES_DIR" ]]; then
        echo "Error: seqr-loading-pipelines directory not found: $PIPELINES_DIR"
        exit 1
    fi
    
    pushd "$PIPELINES_DIR" > /dev/null

    export CLICKHOUSE_DATA_DIR=/var/lib/clickhouse/user_files/seqr-data/pipeline-data

    # optimize_entries() polls until the CollapsingMergeTree -1 rows are gone, sleeping this
    # many seconds between checks -- and it sleeps even when the OPTIMIZE finished instantly.
    # Upstream defaults to 150s, which is sized for production-scale partitions; on a local
    # single-project instance that is almost entirely dead wait. Exported rather than hardcoded
    # so it can still be raised for a big load: CLICKHOUSE_OPTIMIZE_TABLE_WAIT_S=150 bash ...
    export CLICKHOUSE_OPTIMIZE_TABLE_WAIT_S="${CLICKHOUSE_OPTIMIZE_TABLE_WAIT_S:-10}"


    LOAD_CMD="uv run python v03_pipeline/bin/load_to_clickhouse.py \
        --reference-genome $REFERENCE_GENOME \
        --dataset-type $DATASET_TYPE \
        --run-id $RUN_ID \
        --project-guids $PROJECT_GUID \
        --family-guids $FAMILY_GUIDS"
    
    echo "Running: $LOAD_CMD"
    eval "PYTHONPATH=$PIPELINES_DIR $LOAD_CMD"
    
    popd > /dev/null
    echo "✓ Data loaded to ClickHouse"
else
    echo "Step 2: Skipped (--skip-load)"
fi

# Step 3: Register dataset in seqr (if not skipped)
if [[ "$SKIP_REGISTER" == false ]]; then
    echo ""
    echo "Step 3: Registering dataset in seqr..."
    
    cd "$SEQR_DIR"

    # This step runs seqr's manage.py, so it needs the *seqr* environment. Steps 1 and 2
    # run the loading pipelines and activate PIPELINES_UV_ENV at the top of the script;
    # re-sourcing that one here is what produced "cannot import django", because the
    # loading-pipelines environment has no Django in it. SEQR_UV_ENV (and its
    # --seqr-uv-env flag) already existed but was never referenced anywhere.
    #
    # Deactivate first: sourcing a second activate on top of a live one stacks PATH
    # entries and leaves VIRTUAL_ENV pointing at the newer env while the older one is
    # still on PATH behind it.
    SEQR_VENV_ACTIVATE="$HOME/work/tools/uv/environments/$SEQR_UV_ENV/bin/activate"
    if [[ ! -f "$SEQR_VENV_ACTIVATE" ]]; then
        echo "Error: seqr uv environment not found at $SEQR_VENV_ACTIVATE"
        echo "Create it, or point at a different one with --seqr-uv-env NAME."
        exit 1
    fi
    if command -v deactivate > /dev/null 2>&1; then
        deactivate
    fi
    # shellcheck disable=SC1090
    source "$SEQR_VENV_ACTIVATE"

    # Called directly rather than built into a string and eval'd. eval re-parses the
    # command, so any argument containing whitespace or a glob character would be word
    # split or expanded a second time. Quoting the arguments here removes that class of
    # bug entirely. Plain `python` rather than `uv run python` because the environment is
    # already activated: `uv run` picks the project environment when a pyproject.toml is
    # found in the working directory or any parent, which would silently stop using the
    # environment this activated the moment one is added to the repo.
    echo "Running: python manage.py register_clickhouse_dataset $PROJECT_GUID $SAMPLE_TYPE $DATASET_TYPE"
    python manage.py register_clickhouse_dataset \
        "$PROJECT_GUID" \
        "$SAMPLE_TYPE" \
        "$DATASET_TYPE"

    echo "✓ Dataset registered in seqr"
else
    echo "Step 3: Skipped (--skip-register)"
fi

echo ""
echo "=========================================="
echo "✓ Import complete!"
echo "=========================================="
