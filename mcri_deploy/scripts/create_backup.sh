#!/bin/bash

set -ueo pipefail
export PATH="$PATH:/snap/bin"

datestamp="$(date +'%Y-%m-%d')"

BACKUP_PATH="/home/seqr/backups"

echo "Creating backups to $BACKUP_PATH with date $datestamp"

SEQRDB_BACKUP=$BACKUP_PATH/seqrdb-$datestamp.dmp.gz
REFERENCE_DATA_DB_BACKUP=$BACKUP_PATH/reference_data_db-$datestamp.dmp.gz

/usr/bin/docker compose -f /home/seqr/seqr/docker-compose.yml --env-file /home/seqr/seqr/.env exec -T postgres /usr/lib/postgresql/13/bin/pg_dump -U postgres seqrdb | gzip -c > "$SEQRDB_BACKUP"
/usr/bin/docker compose -f /home/seqr/seqr/docker-compose.yml --env-file /home/seqr/seqr/.env exec -T postgres /usr/lib/postgresql/13/bin/pg_dump -U postgres reference_data_db | gzip -c > "$REFERENCE_DATA_DB_BACKUP"

gsutil cp "${SEQRDB_BACKUP}" gs://mcri-seqr-backups/
echo "Backed up $SEQRDB_BACKUP to gs://mcri-seqr-backups/"
gsutil cp "${REFERENCE_DATA_DB_BACKUP}" gs://mcri-seqr-backups/
echo "Backed up $REFERENCE_DATA_DB_BACKUP to gs://mcri-seqr-backups/"
