# redis-cache-obs

```bash
PROJECT_DIR=$(pwd)

COMPOSE_FILE="$PROJECT_DIR/mcri_deploy/docker-compose/docker-compose.yml"
COMPOSE_BUILD_FILE="$PROJECT_DIR/mcri_deploy/docker-compose/docker-compose.build.yml"

# Use seqr.template.env as .env, update ENV vars if necessary
cp "$PROJECT_DIR/mcri_deploy/docker-compose/seqr.template.env" "$PROJECT_DIR/.env" 
COMPOSE_ENV_FILE="$PROJECT_DIR/.env"
source $COMPOSE_ENV_FILE

# Run using docker compose
# Below assumes redis is already running using the same $COMPOSE_FILE
docker compose -f $COMPOSE_FILE -f $COMPOSE_BUILD_FILE --env-file=$COMPOSE_ENV_FILE run -v <path_to_obs_vcf>:/opt/tmp/<obs_vcf_filename> redis-cache-obs -r redis -f /opt/tmp/<obs_vcf_filename>

# Run using docker and mount file to container
docker run -v <path_to_obs_vcf>:/opt/tmp/<obs_vcf_filename> -i gcr.io/mcri-01/mcri-redis-cache-obs:latest -r host.docker.internal -f /opt/tmp/<obs_vcf_filename>

# Run using docker and pipe file to container using STDIN
docker run -i gcr.io/mcri-01/mcri-redis-cache-obs:latest -r host.docker.internal < <path_to_obs_vcf>
```
