# MCRI Deployment

This folder contains documentation and deployment instructions, resources and descriptors specific to MCRI.

The `kubernetes` folder contains Kubernetes deployment descriptors for Elasticsearch service.

The `docker-compose` folder contains docker-compose deployment descriptors for building and deployment Seqr application.

## Prerequisities

* Python 3.9 installed, preferably using an environment manager such as
  [venv](https://docs.python.org/3/library/venv.html)
* Node.js lts/fermium (v14) installed, preferably using an environment such as [nvm](https://github.com/nvm-sh/nvm)

## Getting Started

Below instructions assume `PROJECT_DIR` is set to your seqr checkout path.

```bash
# From here, assume $PROJECT_DIR is the path to your seqr checkout
PROJECT_DIR=$(pwd)
SEQR_REPO="https://github.com/bioinfomethods/seqr"
```

## Source Code Branches

At MCRI, source code branches do not follow the usual convention, below are explanations what each code branch means and
how they're used.

| Name              | Owner          | Description                                                                                                                                                                                                                                             |
| ----------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `upstream/master` | broadinstitute | Refers to Broad's `master` branch, i.e. their production deployment branch                                                                                                                                                                              |
| `upstream/dev`    | broadinstitute | Refers to Broad's `dev` branch, i.e. their development and integration branch                                                                                                                                                                           |
| `master`          | bioinfomethods | Not really used for commits, only one commit ahead of `upstream/master` to clarify README and build related badges.  This branch is kept in sync with `upstream/master` so there is a base to branch off when creating feature/PR branches for upstream |
| `mcri/master`     | bioinfomethods | MCRI's production deployment branch                                                                                                                                                                                                                     |
| `mcri/develop`    | bioinfomethods | MCRI's development and integration branch, typically deployed to MCRI's test server                                                                                                                                                                     |
| `mcri/feat-*`     | bioinfomethods | MCRI's feature branches, typically deployed to local dev environments                                                                                                                                                                                   |

## Building Seqr Application

Make sure you're on the correct branch!

```bash
COMPOSE_FILE="$PROJECT_DIR/mcri_deploy/docker-compose/docker-compose.yml"
COMPOSE_BUILD_FILE="$PROJECT_DIR/mcri_deploy/docker-compose/docker-compose.build.yml"

# Use seqr.template.env as .env, update ENV vars if necessary
cp "$PROJECT_DIR/mcri_deploy/docker-compose/seqr.template.env" "$PROJECT_DIR/.env" 
COMPOSE_ENV_FILE="$PROJECT_DIR/.env"
source $COMPOSE_ENV_FILE

# Build image and adds latest Docker tag by default
docker-compose --verbose \
  -f $COMPOSE_FILE \
  -f $COMPOSE_BUILD_FILE \
  --env-file=$COMPOSE_ENV_FILE \
  build

# After build successful, tag Git repo and Docker repo
# MCRI Seqr follows CalVer, change number after _ (underscore) if deploying multiple times
# on the same day.
export SEQR_VERSION="v$(date +"%Y.%m.%d")_00"
git tag -a "${SEQR_VERSION}" -m "MCRI seqr version ${SEQR_VERSION}"
export SEQR_IMAGE_TAG="${SEQR_VERSION}"
export SEQR_LONG_GIT_TAG=$(git describe --long)

docker tag $(docker images --filter=reference="${CONTAINER_REGISTRY}/${SEQR_IMAGE_NAME}:latest" --quiet) "${CONTAINER_REGISTRY}/${SEQR_IMAGE_NAME}:${SEQR_IMAGE_TAG}"
docker tag $(docker images --filter=reference="${CONTAINER_REGISTRY}/${SEQR_IMAGE_NAME}:latest" --quiet) "${CONTAINER_REGISTRY}/${SEQR_IMAGE_NAME}:${SEQR_LONG_GIT_TAG}"

# Optional: Push to container registry
# This should not be necessary for local development and it'll take a while to upload.
docker-compose -f $COMPOSE_FILE -f $COMPOSE_BUILD_FILE --env-file=$COMPOSE_ENV_FILE push
docker push "${CONTAINER_REGISTRY}/${SEQR_IMAGE_NAME}:latest"
docker push "${CONTAINER_REGISTRY}/${SEQR_IMAGE_NAME}:${SEQR_IMAGE_TAG}"
docker push "${CONTAINER_REGISTRY}/${SEQR_IMAGE_NAME}:${SEQR_LONG_GIT_TAG}"

# Optional: Running and stopping the newly built seqr
docker-compose -f $COMPOSE_FILE -f $COMPOSE_BUILD_FILE --env-file=$COMPOSE_ENV_FILE up -d postgres

docker-compose -f $COMPOSE_FILE -f $COMPOSE_BUILD_FILE --env-file=$COMPOSE_ENV_FILE stop
```
