#!/bin/bash
(
    set -ueo pipefail
    export PATH="$PATH:/snap/bin"

    datestamp=$(date +'%Y-%m-%d')

    outfile="$2/$3_${datestamp}.csv.gz"

    echo "Creating extract: $datestamp"

    cd /home/seqr/seqr

    docker cp "$1" "$(docker-compose ps -q postgres)":/root/

    # /usr/local/bin/docker-compose exec -T postgres psql -U postgres -P format=unaligned -P fieldsep=\, -f "/root/$(basename $1)" seqrdb | gzip -c > "$outfile"
    /usr/local/bin/docker-compose exec -T postgres psql -U postgres --csv -f "/root/$(basename $1)" seqrdb | gzip -c > "$outfile"

    cd "$(dirname "$outfile")"

    gsutil cp "$outfile" gs://mcri-seqr-backups/extracts/

    echo "Done creating extract: $outfile"

) >>/home/seqr/backups/extracts.log 2>&1
