#!/usr/bin/env bash
#
# Open an interactive shell in the running seqr-web ECS Fargate container.
#
# Prerequisites:
#   - AWS CLI v2 installed
#   - Session Manager plugin installed (https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
#   - Appropriate AWS credentials configured
#
# Usage:
#   ./ecs-shell.sh [cluster-name] [service-name] [shell]
#
# If no arguments are provided, the script auto-discovers the cluster and service
# by looking for resources matching the *-seqr-*-cluster / *-seqr-*-seqr-web pattern.

set -euo pipefail

# Parse --command flag for running a specific command instead of interactive shell
SHELL_CMD="/bin/bash"
CLUSTER=""
SERVICE=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--command)
      SHELL_CMD="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

CLUSTER="${POSITIONAL[0]:-}"
SERVICE="${POSITIONAL[1]:-}"
REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

echo "==> Discovering ECS resources in region ${REGION}..."

# Auto-discover cluster
if [[ -z "${CLUSTER}" ]]; then
  CLUSTER=$(aws ecs list-clusters --region "${REGION}" --output text --query \
    "clusterArns[?contains(@, 'seqr')] | [0]" 2>/dev/null || true)
  if [[ -z "${CLUSTER}" || "${CLUSTER}" == "None" ]]; then
    echo "ERROR: Could not find a seqr ECS cluster. Specify the cluster name as the first argument."
    exit 1
  fi
  echo "    Cluster: ${CLUSTER}"
fi

# Auto-discover service
if [[ -z "${SERVICE}" ]]; then
  SERVICE=$(aws ecs list-services --cluster "${CLUSTER}" --region "${REGION}" --output text --query \
    "serviceArns[?contains(@, 'seqr-web')] | [0]" 2>/dev/null || true)
  if [[ -z "${SERVICE}" || "${SERVICE}" == "None" ]]; then
    echo "ERROR: Could not find a seqr-web ECS service. Specify the service name as the second argument."
    exit 1
  fi
  echo "    Service: ${SERVICE}"
fi

# Find a running task
echo "==> Finding a running task..."
TASK_ARN=$(aws ecs list-tasks \
  --cluster "${CLUSTER}" \
  --service-name "${SERVICE}" \
  --desired-status RUNNING \
  --region "${REGION}" \
  --output text \
  --query "taskArns[0]" 2>/dev/null || true)

if [[ -z "${TASK_ARN}" || "${TASK_ARN}" == "None" ]]; then
  echo "ERROR: No running tasks found for service ${SERVICE} in cluster ${CLUSTER}."
  echo "       Check that the service has running tasks: aws ecs list-tasks --cluster ${CLUSTER} --service-name ${SERVICE}"
  exit 1
fi

echo "    Task: ${TASK_ARN}"

# Get the container name
CONTAINER="seqr-web"
echo "    Container: ${CONTAINER}"

# Copy custom terminfo directory if it exists locally
if [ -d ~/.terminfo ]; then
  echo ""
  echo "==> Copying custom terminfo directory to container..."
  TERMINFO_B64=$(tar czf - -C ~ .terminfo | base64)
  aws ecs execute-command \
    --cluster "${CLUSTER}" \
    --task "${TASK_ARN}" \
    --container "${CONTAINER}" \
    --interactive \
    --region "${REGION}" \
    --command "/bin/bash -c 'echo ${TERMINFO_B64} | base64 -d | tar xzf - -C ~'" 2>/dev/null || true
  echo "    ✓ Terminfo directory copied"
fi

echo ""
echo "==> Connecting to container (${SHELL_CMD})..."
echo "    (If this hangs, ensure the Session Manager plugin is installed)"
echo ""

exec aws ecs execute-command \
  --cluster "${CLUSTER}" \
  --task "${TASK_ARN}" \
  --container "${CONTAINER}" \
  --interactive \
  --region "${REGION}" \
  --command "${SHELL_CMD}"
