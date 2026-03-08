#!/usr/bin/env bash
#
# Force a new deployment of the seqr-web ECS Fargate service.
#
# Auto-discovers the ECS cluster and service by looking for resources
# matching the *seqr* pattern.
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#
# Usage:
#   ./deploy-seqr.sh [--timeout <seconds>]
#
# Options:
#   --timeout SECONDS   Deployment timeout (default: 600)
#
# Examples:
#   ./deploy-seqr.sh
#   ./deploy-seqr.sh --timeout 900

set -euo pipefail

DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-600}"
REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      DEPLOY_TIMEOUT="${2:-}"
      if [[ -z "$DEPLOY_TIMEOUT" ]]; then
        echo "Error: --timeout requires a value"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--timeout <seconds>]"
      echo ""
      echo "Options:"
      echo "  --timeout SECONDS   Deployment timeout (default: 600)"
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1"
      echo "Usage: $0 [--timeout <seconds>]"
      exit 1
      ;;
  esac
done

echo "==> Discovering ECS resources in region ${REGION}..."

# Auto-discover cluster
CLUSTER=$(aws ecs list-clusters --region "$REGION" --output text --query \
  "clusterArns[?contains(@, 'seqr')] | [0]" 2>/dev/null || true)
if [[ -z "$CLUSTER" || "$CLUSTER" == "None" ]]; then
  echo "Error: Could not find a seqr ECS cluster."
  exit 1
fi
echo "    Cluster: ${CLUSTER}"

# Auto-discover service
SERVICE=$(aws ecs list-services --cluster "$CLUSTER" --region "$REGION" --output text --query \
  "serviceArns[?contains(@, 'seqr-web')] | [0]" 2>/dev/null || true)
if [[ -z "$SERVICE" || "$SERVICE" == "None" ]]; then
  echo "Error: Could not find a seqr-web ECS service."
  exit 1
fi
echo "    Service: ${SERVICE}"

echo ""
echo "==> Triggering ECS service redeployment..."

aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --force-new-deployment \
  --region "$REGION" \
  --no-cli-pager \
  > /dev/null

echo "    ✓ Redeployment triggered"

# Wait for deployment to complete
ELAPSED=0
POLL_INTERVAL=15
echo ""
echo "==> Waiting for deployment to complete (timeout: ${DEPLOY_TIMEOUT}s)..."

while [ "$ELAPSED" -lt "$DEPLOY_TIMEOUT" ]; do
  # Get deployment info: count of deployments, primary rollout state, running/desired counts
  DEPLOY_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --output json \
    --query 'services[0].deployments' 2>/dev/null) || DEPLOY_INFO="[]"

  DEPLOY_COUNT=$(echo "$DEPLOY_INFO" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null) || DEPLOY_COUNT="0"

  PRIMARY_STATE=$(echo "$DEPLOY_INFO" | python3 -c "
import sys, json
deps = json.load(sys.stdin)
primary = next((d for d in deps if d.get('status') == 'PRIMARY'), None)
if primary:
    print(primary.get('rolloutState', 'UNKNOWN'))
else:
    print('UNKNOWN')
" 2>/dev/null) || PRIMARY_STATE="UNKNOWN"

  PRIMARY_RUNNING=$(echo "$DEPLOY_INFO" | python3 -c "
import sys, json
deps = json.load(sys.stdin)
primary = next((d for d in deps if d.get('status') == 'PRIMARY'), None)
print(primary.get('runningCount', 0) if primary else 0)
" 2>/dev/null) || PRIMARY_RUNNING="0"

  PRIMARY_DESIRED=$(echo "$DEPLOY_INFO" | python3 -c "
import sys, json
deps = json.load(sys.stdin)
primary = next((d for d in deps if d.get('status') == 'PRIMARY'), None)
print(primary.get('desiredCount', 0) if primary else 0)
" 2>/dev/null) || PRIMARY_DESIRED="0"

  if [[ "$PRIMARY_STATE" == "COMPLETED" && "$DEPLOY_COUNT" == "1" ]]; then
    echo "    ✓ Deployment complete (running: ${PRIMARY_RUNNING}/${PRIMARY_DESIRED})"
    exit 0
  fi

  if [[ "$PRIMARY_STATE" == "FAILED" ]]; then
    echo "    ✗ Deployment FAILED"
    echo ""
    echo "    Check events: aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE} --query 'services[0].events[:5]'"
    exit 1
  fi

  echo "    Deploying... state=${PRIMARY_STATE} running=${PRIMARY_RUNNING}/${PRIMARY_DESIRED} deployments=${DEPLOY_COUNT} (${ELAPSED}s elapsed)"
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$ELAPSED" -ge "$DEPLOY_TIMEOUT" ]; then
  echo "    ⚠ Deployment timeout reached (${DEPLOY_TIMEOUT}s) — deployment may still be in progress"
  echo "    Monitor: aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE} --query 'services[0].deployments'"
  exit 2
fi
