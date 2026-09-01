#!/bin/bash

echo 
echo "Seqr Clickhoust Reset Script"
echo


docker compose down

rm -rf data/postgres

docker volume rm  seqrc-test_clickhouse-data 
docker volume rm seqrc-test_clickhouse-in-memory 

echo
echo "Starting postgres ..."
echo

docker compose up -d postgres redis

sleep 5

echo
echo "Starting clickhouse  ..."
echo
docker compose up -d clickhouse

sleep 5

if [ ! -e ui/dist ];
then
    nvm use || { echo "Please install nvm" ; exit 1; }

    echo "Building ui assets ..."
    echo
    (cd ui && npm ci && npm run build)
fi


echo
echo "Starting seqr ..."
echo

docker compose up -d seqr

docker compose logs --follow

