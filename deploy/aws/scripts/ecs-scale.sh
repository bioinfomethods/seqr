#!/usr/bin/env bash
#
# Scale the seqr-web ECS Fargate service to a desired task count.
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#   - Appropriate AWS credentials configured
#
# Usage:
#   ./ecs-scale.sh <desired-count>
#
# Examples:
#   ./ecs-scale.sh 0    # Scale down (stop all tasks)
#   ./ecs-scale.sh 1    # Scale to 1 task (default)
#   ./ecs-scale.sh 3    # Scale to 3 tasks
#
# If cluster/service are not provided, the script auto-discovers them
# by looking for resources matching the *seqr* pattern.

set -euo pipefail

DESIRED_COUNT="${1:-}"
REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

if [[ -z "${DESIRED_COUNT}" ]]; then
  echo "Usage: $0 <desired-count>"
  echo ""
  echo "  desired-count: Number of Fargate tasks to run (0 to stop all)"
  echo ""
  echo "Examples:"
  echo "  $0 0    # Scale down (stop all tasks)"
  echo "  $0 1    # Scale to 1 task"
  echo "  $0 3    # Scale to 3 tasks"
  exit 1
fi

# Validate desired count is a non-negative integer
if ! [[ "${DESIRED_COUNT}" =~ ^[0-9]+$ ]]; then
  echo "Error: desired-count must be a non-negative integer, got: ${DESIRED_COUNT}"
  exit 1
fi

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

# Get current desired count
CURRENT=$(aws ecs describe-services \
  --cluster "${CLUSTER}" \
  --services "${SERVICE}" \
  --region "${REGION}" \
  --output text \
  --query 'services[0].desiredCount' 2>/dev/null) || CURRENT="unknown"
echo "    Current desired count: ${CURRENT}"

if [[ "${CURRENT}" == "${DESIRED_COUNT}" ]]; then
  echo ""
  echo "==> Already at desired count ${DESIRED_COUNT}, nothing to do."
  exit 0
fi

# Scale the service
echo ""
echo "==> Scaling service to ${DESIRED_COUNT}..."
aws ecs update-service \
  --cluster "${CLUSTER}" \
  --service "${SERVICE}" \
  --desired-count "${DESIRED_COUNT}" \
  --region "${REGION}" \
  --no-cli-pager \
  > /dev/null

echo "    ✓ Desired count set to ${DESIRED_COUNT}"

# If scaling down to 0, optionally wait for drain
if [[ "${DESIRED_COUNT}" -eq 0 ]]; then
  echo ""
  echo "==> Waiting for tasks to drain..."
  DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-120}"
  ELAPSED=0
  while [ "$ELAPSED" -lt "$DRAIN_TIMEOUT" ]; do
    RUNNING=$(aws ecs list-tasks \
      --cluster "${CLUSTER}" \
      --service-name "${SERVICE}" \
      --desired-status RUNNING \
      --region "${REGION}" \
      --output text \
      --query 'taskArns | length(@)' 2>/dev/null) || RUNNING="0"

    if [ "$RUNNING" -eq 0 ]; then
      echo "    ✓ All tasks drained"
      break
    fi

    echo "    Still ${RUNNING} task(s) running... (${ELAPSED}s elapsed)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
  done

  if [ "$ELAPSED" -ge "$DRAIN_TIMEOUT" ]; then
    echo "    Warning: Drain timeout reached (${DRAIN_TIMEOUT}s), tasks may still be stopping"
  fi
fi

echo ""
echo "==> Done."
