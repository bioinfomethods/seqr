#!/bin/bash

source scripts/aws-env.sh

aws_env

docker build -t 487143049215.dkr.ecr.ap-southeast-2.amazonaws.com/mcri-seqr-dev-seqr-web:latest -f deploy/docker/seqr/Dockerfile . 

aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 487143049215.dkr.ecr.ap-southeast-2.amazonaws.com 

docker push 487143049215.dkr.ecr.ap-southeast-2.amazonaws.com/mcri-seqr-dev-seqr-web:latest 
