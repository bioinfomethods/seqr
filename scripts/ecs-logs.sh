#!/usr/bin/env bash
#
# Show log output from the seqr-web ECS Fargate task.
#
# Usage:
#   scripts/ecs-logs.sh                          # defaults: prefix=mcri, env=dev
#   scripts/ecs-logs.sh -e prod                  # prod environment
#   scripts/ecs-logs.sh -p myorg -e test         # custom prefix + environment
#   scripts/ecs-logs.sh -f                       # follow/tail logs
#   scripts/ecs-logs.sh -n 200                   # last 200 lines
#   scripts/ecs-logs.sh -s "2025-03-01T00:00:00" # logs since timestamp
#
# Prerequisites:
#   - AWS CLI v2 installed
#   - Valid AWS credentials (use: source scripts/aws-env.sh && aws_env)
#

set -euo pipefail

# Defaults
PREFIX="mcri"
ENV="dev"
FOLLOW=false
NUM_LINES=100
SINCE=""
REGION=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Show logs from the seqr-web ECS Fargate task.

Options:
  -p PREFIX      Resource prefix (default: mcri)
  -e ENV         Environment: dev, test, prod (default: dev)
  -r REGION      AWS region (default: from AWS config or ap-southeast-2)
  -f             Follow/tail logs (streams new log events)
  -n LINES       Number of recent log lines to show (default: 100)
  -s TIMESTAMP   Show logs since timestamp (e.g. "2025-03-01T00:00:00")
  -h             Show this help message

Examples:
  $(basename "$0")                        # dev logs, last 100 lines
  $(basename "$0") -e prod -f             # tail prod logs
  $(basename "$0") -n 500                 # last 500 lines
  $(basename "$0") -s "1h"               # logs from last hour (awslogs shorthand)
EOF
    exit 0
}

while getopts "p:e:r:fn:s:h" opt; do
    case "$opt" in
        p) PREFIX="$OPTARG" ;;
        e) ENV="$OPTARG" ;;
        r) REGION="$OPTARG" ;;
        f) FOLLOW=true ;;
        n) NUM_LINES="$OPTARG" ;;
        s) SINCE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate environment
if [[ ! "$ENV" =~ ^(dev|test|prod)$ ]]; then
    echo "ERROR: Environment must be one of: dev, test, prod (got: $ENV)" >&2
    exit 1
fi

# Determine region
if [[ -z "$REGION" ]]; then
    REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-southeast-2}}"
fi

# Construct resource names (matches Terraform naming in main.tf and fargate.tf)
NAME_PREFIX="${PREFIX}-seqr-${ENV}"
CLUSTER_NAME="${NAME_PREFIX}-cluster"
SERVICE_NAME="${NAME_PREFIX}-seqr-web"
LOG_GROUP="/ecs/${NAME_PREFIX}-seqr-web"
CONTAINER_NAME="seqr-web"

echo "=== seqr-web ECS Log Viewer ==="
echo "  Prefix:      ${PREFIX}"
echo "  Environment: ${ENV}"
echo "  Region:      ${REGION}"
echo "  Cluster:     ${CLUSTER_NAME}"
echo "  Service:     ${SERVICE_NAME}"
echo "  Log group:   ${LOG_GROUP}"
echo ""

# ---------------------------------------------------------------
# Check AWS credentials
# ---------------------------------------------------------------
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
    echo "ERROR: No valid AWS credentials found." >&2
    echo "" >&2
    echo "To authenticate, run:" >&2
    echo "  source scripts/aws-env.sh && aws_env" >&2
    exit 1
fi
CALLER_IDENTITY=$(aws sts get-caller-identity --region "$REGION" --output text --query 'Arn')
echo "  Authenticated as: ${CALLER_IDENTITY}"
echo ""

# ---------------------------------------------------------------
# Verify ECS cluster exists
# ---------------------------------------------------------------
echo "Looking up ECS cluster: ${CLUSTER_NAME}..."
CLUSTER_STATUS=$(aws ecs describe-clusters \
    --region "$REGION" \
    --clusters "$CLUSTER_NAME" \
    --query "clusters[0].status" \
    --output text 2>/dev/null || echo "MISSING")

if [[ "$CLUSTER_STATUS" == "None" || "$CLUSTER_STATUS" == "MISSING" ]]; then
    echo "ERROR: ECS cluster '${CLUSTER_NAME}' not found in region ${REGION}." >&2
    echo "" >&2
    echo "Available clusters:" >&2
    aws ecs list-clusters --region "$REGION" --query "clusterArns[]" --output table 2>/dev/null || true
    exit 1
fi
echo "  Cluster status: ${CLUSTER_STATUS}"

# ---------------------------------------------------------------
# Verify ECS service exists and get running task info
# ---------------------------------------------------------------
echo "Looking up ECS service: ${SERVICE_NAME}..."
SERVICE_JSON=$(aws ecs describe-services \
    --region "$REGION" \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --query "services[0]" \
    --output json 2>/dev/null || echo "{}")

SERVICE_STATUS=$(echo "$SERVICE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','MISSING'))" 2>/dev/null || echo "MISSING")
RUNNING_COUNT=$(echo "$SERVICE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('runningCount',0))" 2>/dev/null || echo "0")
DESIRED_COUNT=$(echo "$SERVICE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('desiredCount',0))" 2>/dev/null || echo "0")

if [[ "$SERVICE_STATUS" == "MISSING" || "$SERVICE_STATUS" == "null" ]]; then
    echo "ERROR: ECS service '${SERVICE_NAME}' not found in cluster '${CLUSTER_NAME}'." >&2
    echo "" >&2
    echo "Available services:" >&2
    aws ecs list-services --region "$REGION" --cluster "$CLUSTER_NAME" --query "serviceArns[]" --output table 2>/dev/null || true
    exit 1
fi
echo "  Service status: ${SERVICE_STATUS} (running: ${RUNNING_COUNT}/${DESIRED_COUNT})"

# ---------------------------------------------------------------
# List recent tasks (running + stopped) for context
# ---------------------------------------------------------------
echo ""
echo "Recent tasks:"
TASK_ARNS=$(aws ecs list-tasks \
    --region "$REGION" \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --query "taskArns[]" \
    --output text 2>/dev/null || echo "")

STOPPED_TASK_ARNS=$(aws ecs list-tasks \
    --region "$REGION" \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status STOPPED \
    --query "taskArns[]" \
    --output text 2>/dev/null || echo "")

ALL_TASK_ARNS="${TASK_ARNS} ${STOPPED_TASK_ARNS}"
ALL_TASK_ARNS=$(echo "$ALL_TASK_ARNS" | xargs -n1 | sort -u | xargs)

if [[ -n "$ALL_TASK_ARNS" && "$ALL_TASK_ARNS" != " " ]]; then
    aws ecs describe-tasks \
        --region "$REGION" \
        --cluster "$CLUSTER_NAME" \
        --tasks $ALL_TASK_ARNS \
        --query "tasks[].{TaskId: taskArn, Status: lastStatus, StoppedReason: stoppedReason, CreatedAt: createdAt}" \
        --output table 2>/dev/null || echo "  (unable to describe tasks)"
else
    echo "  No tasks found (running or recently stopped)."
fi

# ---------------------------------------------------------------
# Verify log group exists
# ---------------------------------------------------------------
echo ""
echo "Checking log group: ${LOG_GROUP}..."
LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
    --region "$REGION" \
    --log-group-name-prefix "$LOG_GROUP" \
    --query "logGroups[?logGroupName=='${LOG_GROUP}'].logGroupName" \
    --output text 2>/dev/null || echo "")

if [[ -z "$LOG_GROUP_EXISTS" ]]; then
    echo "ERROR: Log group '${LOG_GROUP}' not found." >&2
    echo "The task may not have started yet, or the log group hasn't been created." >&2
    exit 1
fi
echo "  Log group found."

# ---------------------------------------------------------------
# Fetch logs
# ---------------------------------------------------------------
echo ""
echo "--- Logs (last ${NUM_LINES} events) ---"
echo ""

LOG_ARGS=(
    logs tail "$LOG_GROUP"
    --region "$REGION"
    --format short
)

if [[ "$FOLLOW" == true ]]; then
    LOG_ARGS+=(--follow)
fi

if [[ -n "$SINCE" ]]; then
    LOG_ARGS+=(--since "$SINCE")
else
    # Default: use --since with a relative time to limit output
    LOG_ARGS+=(--since "1h")
fi

# aws logs tail doesn't support a line limit directly, so we use it in follow
# mode or pipe through tail for non-follow mode
if [[ "$FOLLOW" == true ]]; then
    aws "${LOG_ARGS[@]}"
else
    aws "${LOG_ARGS[@]}" 2>/dev/null | tail -n "$NUM_LINES"
fi
