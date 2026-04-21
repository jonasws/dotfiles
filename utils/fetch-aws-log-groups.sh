#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <aws-profile>" >&2
  exit 1
fi

AWS_PROFILE="$1"

aws logs describe-log-groups \
  --profile $AWS_PROFILE \
  --query 'logGroups[?storedBytes > `0`].logGroupName' \
  --output text |
  tr '\t' '\n'
