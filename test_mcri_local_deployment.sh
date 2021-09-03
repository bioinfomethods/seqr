#!/usr/bin/env bash

set -ex

cp "./mcri_deploy/docker-compose/seqr.template.env" "./.env"
cp "./mcri_deploy/docker-compose/docker-compose.yml" "./"

docker-compose up -d seqr
docker-compose logs postgres
docker-compose logs redis
sleep 30
docker-compose logs seqr
echo -ne 'testpassword\n' docker-compose exec seqr python manage.py createsuperuser --username test --email test@test.com
