#!/bin/bash
(
        set -ueo pipefail
        export PATH="$PATH:/snap/bin"

        datestamp=$(date +'%Y-%m-%d')

        echo "Creating backup: $datestamp"

        cd /home/seqr/seqr

        /usr/local/bin/docker-compose exec -T postgres /usr/lib/postgresql/12/bin/pg_dump -U postgres seqrdb | gzip -c > "/home/seqr/backups/seqrdb-${datestamp}.dmp.gz"

        cd /home/seqr/backups

        # We expect the last good backup is our current backup but it may not be - so we only copy the most recent one that has
        # expected size to the cloud
        LAST_GOOD_BACKUP=$(find /home/seqr/backups -size +15000 -iname '*.dmp.gz' | xargs ls -t -1 | head -n 1)

        gsutil cp "${LAST_GOOD_BACKUP}" gs://mcri-seqr-backups/

        echo "Done creating backup: $datestamp"

) >> /home/seqr/backups/backup.log 2>&1
