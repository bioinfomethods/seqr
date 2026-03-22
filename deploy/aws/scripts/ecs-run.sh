#!/usr/bin/env bash
#
# Run a long-running command in the seqr-web ECS Fargate container,
# detached from the session so it survives disconnects/timeouts.
#
# Usage:
#   ./ecs-run.sh "python manage.py reload_clinvar_all_variants --file s3://bucket/file.xml.gz"
#   ./ecs-run.sh "python manage.py migrate --database clickhouse_write"
#
# The command runs via nohup in the background. Output is written to a log file
# inside the container. Reconnect with ecs-shell.sh to check progress.

set -euo pipefail

COMMAND="${1:-}"
REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

if [[ -z "${COMMAND}" ]]; then
  echo "Usage: $0 <command>"
  echo ""
  echo "Examples:"
  echo "  $0 \"python manage.py reload_clinvar_all_variants --file s3://bucket/ClinVarVCVRelease.xml.gz\""
  echo "  $0 \"python manage.py migrate --database clickhouse_write\""
  exit 1
fi

LOG_FILE="/tmp/ecs-run-$(date +%Y%m%d_%H%M%S).log"

echo "==> Discovering ECS resources in region ${REGION}..."

# Auto-discover cluster
CLUSTER=$(aws ecs list-clusters --region "${REGION}" --output text --query \
  "clusterArns[?contains(@, 'seqr')] | [0]" 2>/dev/null || true)
if [[ -z "${CLUSTER}" || "${CLUSTER}" == "None" ]]; then
  echo "ERROR: Could not find a seqr ECS cluster."
  exit 1
fi
echo "    Cluster: ${CLUSTER}"

# Auto-discover service
SERVICE=$(aws ecs list-services --cluster "${CLUSTER}" --region "${REGION}" --output text --query \
  "serviceArns[?contains(@, 'seqr-web')] | [0]" 2>/dev/null || true)
if [[ -z "${SERVICE}" || "${SERVICE}" == "None" ]]; then
  echo "ERROR: Could not find a seqr-web ECS service."
  exit 1
fi
echo "    Service: ${SERVICE}"

# Find a running task
TASK_ARN=$(aws ecs list-tasks \
  --cluster "${CLUSTER}" \
  --service-name "${SERVICE}" \
  --desired-status RUNNING \
  --region "${REGION}" \
  --output text \
  --query "taskArns[0]" 2>/dev/null || true)

if [[ -z "${TASK_ARN}" || "${TASK_ARN}" == "None" ]]; then
  echo "ERROR: No running tasks found."
  exit 1
fi
echo "    Task: ${TASK_ARN}"

CONTAINER="seqr-web"

echo ""
echo "==> Running command detached in container..."
echo "    Command:  ${COMMAND}"
echo "    Log file: ${LOG_FILE}"
echo ""

# Run the command via nohup so it survives session termination.
# We use bash -c to wrap the whole thing including redirection.
aws ecs execute-command \
  --cluster "${CLUSTER}" \
  --task "${TASK_ARN}" \
  --container "${CONTAINER}" \
  --interactive \
  --region "${REGION}" \
  --command "/bin/bash -c 'nohup ${COMMAND} > ${LOG_FILE} 2>&1 & PID=\$!; echo \"Started PID: \$PID\"; echo \"Log file: ${LOG_FILE}\"; echo \"Check progress: tail -f ${LOG_FILE}\"; echo \"Check if running: ps -p \$PID\"'"

echo ""
echo "==> Command launched. Reconnect with ecs-shell.sh to monitor:"
echo "    tail -f ${LOG_FILE}"
