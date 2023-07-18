#!/bin/bash
#
# Launch archie agent and run as daemon using jsvc

set -eo pipefail

#######################################
# info() and error() log messages to STDOUT and STDERR respectively.
# Globals:
#   None
# Arguments:
#   Variable args written out as string
# Outputs:
#   Writes message to STDOUT or STDERR
#######################################
function info() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z') INFO $(basename "$0")] $*" >&1
}

function error() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z') ERROR $(basename "$0")] $*" >&2
}

function usage() {
    info "usage: build_seqr.sh {test|prod|info} <seqr|all>"
}

check_command() {
    if ! command -v "$1" &> /dev/null
    then
        error "$1 could not be found"
        exit 3
    fi
}

check_command "git"
check_command "docker"

if [ -z "$1" ]; then
    usage
    exit 3
fi

if [ -z "$2" ]; then
    BUILD_COMPONENT="all"
else
    BUILD_COMPONENT="$2"
fi

if [ -z "$3" ]; then
    BUILD_OPTS="--progress auto"
else
    BUILD_OPTS="--progress auto $3"
fi

set -euo pipefail

build() {
    PROJECT_DIR="$HOME/$1"
    if [ ! -d "$PROJECT_DIR" ]; then
      error "$PROJECT_DIR does not exist"
      exit 3
    fi
    cd "$PROJECT_DIR"
    info "Running build for $PROJECT_DIR"

    git pull --rebase --recurse-submodules
    git submodule update --init --recursive

    COMPOSE_FILE="$PROJECT_DIR/mcri_deploy/docker-compose/docker-compose.yml"
    COMPOSE_BUILD_FILE="$PROJECT_DIR/mcri_deploy/docker-compose/docker-compose.build.yml"

    cp "$PROJECT_DIR/mcri_deploy/docker-compose/seqr.template.env" "$PROJECT_DIR/.env"
    COMPOSE_ENV_FILE="$PROJECT_DIR/.env"
    
    for line in $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
    do
        eval "$line"
    done

    # Tagging
    SEQR_GIT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
    SEQR_GIT_BRANCH_TAG=${SEQR_GIT_BRANCH_NAME/\//_}
    SEQR_LONG_GIT_TAG=$(git describe --long --always)

    if [ "$BUILD_COMPONENT" == "all" ]; then
        build_all "$@"
    elif [ "$BUILD_COMPONENT" == "seqr" ]; then
        build_seqr "$@"
    else
        usage
        exit 3
    fi
}

build_seqr() {
    info "Building seqr component only"
    set -x
    docker compose --verbose \
      -f "$COMPOSE_FILE" \
      -f "$COMPOSE_BUILD_FILE" \
      --env-file="$COMPOSE_ENV_FILE" \
      build $BUILD_OPTS seqr

    docker compose --verbose \
      -f "$COMPOSE_FILE" \
      -f "$COMPOSE_BUILD_FILE" \
      --env-file="$COMPOSE_ENV_FILE" \
      push seqr

    docker tag "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_IMAGE_TAG" "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker push "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"

    docker tag "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_IMAGE_TAG" "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker push "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_LONG_GIT_TAG"

    if [[ "$1" == "seqr" ]]; then
        SEQR_VERSION="$(git describe --always)"
        docker tag "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_IMAGE_TAG" "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_VERSION"
        docker push "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_VERSION"
    fi
}

build_all() {
    info "Building all components"
    set -x
    docker compose --verbose \
      -f "$COMPOSE_FILE" \
      -f "$COMPOSE_BUILD_FILE" \
      --env-file="$COMPOSE_ENV_FILE" \
      build $BUILD_OPTS

    docker compose --verbose \
      -f "$COMPOSE_FILE" \
      -f "$COMPOSE_BUILD_FILE" \
      --env-file="$COMPOSE_ENV_FILE" \
      push

    docker compose --profile cache --verbose \
      -f "$COMPOSE_FILE" \
      -f "$COMPOSE_BUILD_FILE" \
      --env-file="$COMPOSE_ENV_FILE" \
      build $BUILD_OPTS

    docker compose --profile cache --verbose \
      -f "$COMPOSE_FILE" \
      -f "$COMPOSE_BUILD_FILE" \
      --env-file="$COMPOSE_ENV_FILE" \
      push

    docker tag "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_IMAGE_TAG" "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker tag "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$POSTGRES_IMAGE_TAG" "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker tag "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$REDIS_IMAGE_TAG" "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker tag "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$REDIS_CACHE_OBS_IMAGE_TAG" "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker push "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker push "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker push "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"
    docker push "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$SEQR_GIT_BRANCH_TAG"

    docker tag "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_IMAGE_TAG" "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker tag "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$POSTGRES_IMAGE_TAG" "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker tag "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$REDIS_IMAGE_TAG" "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker tag "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$REDIS_CACHE_OBS_IMAGE_TAG" "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker push "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker push "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker push "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$SEQR_LONG_GIT_TAG"
    docker push "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$SEQR_LONG_GIT_TAG"

    if [[ "$1" == "seqr" ]]; then
        SEQR_VERSION="$(git describe --always)"
        docker tag "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_IMAGE_TAG" "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_VERSION"
        docker tag "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$POSTGRES_IMAGE_TAG" "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$SEQR_VERSION"
        docker tag "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$REDIS_IMAGE_TAG" "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$SEQR_VERSION"
        docker tag "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$REDIS_CACHE_OBS_IMAGE_TAG" "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$SEQR_VERSION"
        docker push "$CONTAINER_REGISTRY/$SEQR_IMAGE_NAME:$SEQR_VERSION"
        docker push "$CONTAINER_REGISTRY/$POSTGRES_IMAGE_NAME:$SEQR_VERSION"
        docker push "$CONTAINER_REGISTRY/$REDIS_IMAGE_NAME:$SEQR_VERSION"
        docker push "$CONTAINER_REGISTRY/$REDIS_CACHE_OBS_IMAGE_NAME:$SEQR_VERSION"
    fi
}

case "$1" in
test)
    build "seqr-test"
    ;;
prod)
    build "seqr"
    ;;
*)
    usage
    exit 3
    ;;
esac
