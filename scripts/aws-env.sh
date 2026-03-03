#!/usr/bin/env bash
#
# Source this file to get the aws_env function:
#
#   source scripts/aws-env.sh
#   aws_env                        # uses default profile "seqrclickhouse"
#   aws_env my-other-profile       # uses a custom profile
#

aws_env() {
    local profile="${1:-seqrclickhouse}"

    echo "Fetching credentials for profile: ${profile} ..."

    local creds
    creds=$(aws configure export-credentials --profile "$profile" --format env 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to get credentials. Have you run 'aws sso login --profile ${profile}'?" >&2
        echo "$creds" >&2
        return 1
    fi

    eval "$creds"

    echo "AWS environment variables set for profile: ${profile}"
    echo "  AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:0:8}..."
    echo "  AWS_SECRET_ACCESS_KEY=****"
    echo "  AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:0:8}..."
}
