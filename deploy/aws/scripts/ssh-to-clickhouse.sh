#!/bin/bash

(
    ssh-agent

    ssh-add ~/.ssh/id_ed25519_mcri_aws

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_ed25519_mcri_aws -J  ec2-user@3.106.87.137   ec2-user@172.31.254.7
)

echo "Done"

