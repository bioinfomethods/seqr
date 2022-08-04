#!/bin/bash
(
        set -ueo pipefail
        export PATH="$PATH:/snap/bin"

        datestamp=$(date +'%Y-%m-%d')

        echo "Creating backup: $datestamp"

        cd /home/seqr/seqr

        /usr/local/bin/docker-compose exec -T postgres /usr/lib/postgresql/12/bin/pg_dump -U postgres seqrdb | gzip -c > "/home/seqr/backups/seqrdb-${datestamp}.dmp.gz"
        /usr/local/bin/docker-compose exec -T postgres /usr/lib/postgresql/12/bin/pg_dump -U postgres reference_data_db | gzip -c > "/home/seqr/backups/reference_data_db-${datestamp}.dmp.gz"

        cd /home/seqr/backups

        # We expect the last good backup is our current backup but it may not be - so we only copy the most recent one that has
        # expected size to the cloud
        SEQRDB_LAST_GOOD_BACKUP=$(find /home/seqr/backups -size +15000 -iname "seqrdb*.dmp.gz" | sort -r | head -n 1)
        REFERENCEDB_LAST_GOOD_BACKUP=$(find /home/seqr/backups -size +15000 -iname "reference_data_db*.dmp.gz" | sort -r | head -n 1)

        gsutil cp "${SEQRDB_LAST_GOOD_BACKUP}" gs://mcri-seqr-backups/
        gsutil cp "${REFERENCEDB_LAST_GOOD_BACKUP}" gs://mcri-seqr-backups/

        echo "Done creating backup: $datestamp"

) >> /home/seqr/backups/backup.log 2>&1
