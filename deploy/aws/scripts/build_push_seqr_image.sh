#!/usr/bin/env bash
#
# Build the seqr-web Docker image, push it to ECR, and optionally trigger
# an ECS service redeployment.
#
# The ECR repository URL, AWS account ID, and region are auto-discovered
# from Terraform outputs (requires tofu to be installed).
#
# Prerequisites:
#   - Docker installed and running
#   - AWS CLI v2 installed and configured
#   - OpenTofu (tofu) installed
#   - Run from the repository root (or the script will cd there)
#
# Usage:
#   ./build_push_seqr_image.sh [--deploy] [--tag <tag>]
#
# Options:
#   --deploy    After pushing, force a new ECS service deployment
#   --tag TAG   Docker image tag (default: latest)
#
# Examples:
#   ./build_push_seqr_image.sh
#   ./build_push_seqr_image.sh --deploy
#   ./build_push_seqr_image.sh --tag v1.2.3 --deploy

set -euo pipefail

# ---- Parse arguments ----
DEPLOY=false
IMAGE_TAG="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy)
      DEPLOY=true
      shift
      ;;
    --tag)
      IMAGE_TAG="${2:-}"
      if [[ -z "$IMAGE_TAG" ]]; then
        echo "Error: --tag requires a value"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--deploy] [--tag <tag>]"
      echo ""
      echo "Options:"
      echo "  --deploy    After pushing, force a new ECS service deployment"
      echo "  --tag TAG   Docker image tag (default: latest)"
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1"
      echo "Usage: $0 [--deploy] [--tag <tag>]"
      exit 1
      ;;
  esac
done

REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

# ---- Locate repository root ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_AWS_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$DEPLOY_AWS_DIR/../.." && pwd)"

# Verify we're in the right place
if [[ ! -f "$REPO_ROOT/deploy/docker/seqr/Dockerfile" ]]; then
  echo "Error: Cannot find Dockerfile at deploy/docker/seqr/Dockerfile"
  echo "       Make sure this script is run from the repository root or deploy/aws/scripts/"
  exit 1
fi

# ---- Auto-discover ECR repository from Terraform outputs ----
echo "==> Retrieving ECR repository URL from Terraform outputs..."
cd "$DEPLOY_AWS_DIR"

ECR_REPO_URL=$(tofu output -raw ecr_repository_seqr_web_url 2>/dev/null || true)
if [[ -z "$ECR_REPO_URL" ]]; then
  echo "Error: Could not retrieve ecr_repository_seqr_web_url from Terraform outputs."
  echo "       Ensure 'tofu output -raw ecr_repository_seqr_web_url' works in deploy/aws/"
  exit 1
fi

# Extract the registry URL (everything before the first /)
ECR_REGISTRY="${ECR_REPO_URL%%/*}"

echo "    ECR Registry: ${ECR_REGISTRY}"
echo "    ECR Repository: ${ECR_REPO_URL}"
echo "    Image Tag: ${IMAGE_TAG}"

FULL_IMAGE="${ECR_REPO_URL}:${IMAGE_TAG}"

# ---- Build Docker image ----
echo ""
echo "==> Building Docker image..."
cd "$REPO_ROOT"

docker build \
  -t "$FULL_IMAGE" \
  -f deploy/docker/seqr/Dockerfile \
  .

echo "    ✓ Build complete: ${FULL_IMAGE}"

# ---- Authenticate with ECR ----
echo ""
echo "==> Authenticating with ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "    ✓ Authenticated"

# ---- Push image ----
echo ""
echo "==> Pushing image to ECR..."
docker push "$FULL_IMAGE"

echo "    ✓ Push complete: ${FULL_IMAGE}"

# ---- Optionally trigger ECS redeployment ----
if [[ "$DEPLOY" == "true" ]]; then
  echo ""
  echo "==> Triggering ECS service redeployment..."

  # Auto-discover ECS cluster and service
  CLUSTER=$(aws ecs list-clusters --region "$REGION" --output text --query \
    "clusterArns[?contains(@, 'seqr')] | [0]" 2>/dev/null || true)
  if [[ -z "$CLUSTER" || "$CLUSTER" == "None" ]]; then
    echo "Error: Could not find a seqr ECS cluster."
    exit 1
  fi
  echo "    Cluster: ${CLUSTER}"

  SERVICE=$(aws ecs list-services --cluster "$CLUSTER" --region "$REGION" --output text --query \
    "serviceArns[?contains(@, 'seqr-web')] | [0]" 2>/dev/null || true)
  if [[ -z "$SERVICE" || "$SERVICE" == "None" ]]; then
    echo "Error: Could not find a seqr-web ECS service."
    exit 1
  fi
  echo "    Service: ${SERVICE}"

  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --force-new-deployment \
    --region "$REGION" \
    --no-cli-pager \
    > /dev/null

  echo "    ✓ Redeployment triggered — new tasks will pull ${FULL_IMAGE}"
  echo "    Monitor progress: aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE} --query 'services[0].deployments'"
fi

echo ""
echo "==> Done."
