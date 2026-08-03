#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $(basename "$0") <aws-profile> <log-group-name>" >&2
  exit 1
fi

AWS_PROFILE="$1"
LOG_GROUP="$2"

# Activity summary for a log group, used as a tv preview. CloudWatch exposes
# no producer/source metadata on streams (an ECS service, log driver, etc. is
# only ever implied by the stream name), so we summarise timing instead: the
# most recent event across streams and how many streams were sampled.
read -r latest_ms count < <(
  aws logs describe-log-streams \
    --profile "$AWS_PROFILE" \
    --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime --descending \
    --max-items 20 \
    --query 'logStreams[].lastEventTimestamp' \
    --output text 2>/dev/null |
    tr '\t' '\n' |
    awk '
      # Streams that never logged have a null lastEventTimestamp, rendered as
      # "None" by --output text; skip those, and force numeric comparison so a
      # stray non-number cannot poison the max via string comparison.
      $1 ~ /^[0-9]+$/ { count++; v = $1 + 0; if (v > latest) latest = v }
      END { print latest + 0, count + 0 }'
)

if [[ "$count" -eq 0 ]]; then
  echo "No streams / no recent activity."
  exit 0
fi

# bttf does datetime formatting; CloudWatch timestamps are epoch milliseconds.
when="$(bttf time parse -f '%s' "$((latest_ms / 1000))" | bttf time in system |
  bttf time fmt -f '%Y-%m-%d %H:%M %Z')"
ago="$(bttf span since "$(bttf time parse -f '%s' "$((latest_ms / 1000))")" |
  bttf span round -l year -s hour)"

printf "Most recent event: %s (%s ago)\n" "$when" "$ago"
printf "Streams sampled:   %d (newest by last event)\n" "$count"
