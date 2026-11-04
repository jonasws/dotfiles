#!/usr/bin/env bash
# Live TML view of an ECS service's most recent service deployment, drawn in a
# tuios pane. Uses whatever AWS credentials are in the environment, finds the
# cluster itself, and asks for the service with gum when none is given.
#
#   bash watch-ecs-deployment.sh [SERVICE] [--poll SECONDS] [--no-focus]
#
# Stops polling once the deployment has finished, and blocks until the pane is
# closed. Ctrl+C here or in the pane ends both, and the focus comes back here.
# The pane opens in this pane's tuios session and workspace.
set -uo pipefail

service=""
poll=10
focus=true
while (($#)); do
  case "$1" in
    --poll) poll=$2; shift 2 ;;
    --no-focus) focus=false; shift ;;
    -*) echo "unknown flag $1" >&2; exit 2 ;;
    *) service=$1; shift ;;
  esac
done

export AWS_REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}
here=$(cd "$(dirname "$0")" && pwd)

account=$(aws sts get-caller-identity --query Account --output text) || {
  echo "No working AWS credentials; run it under fnox exec -P <profile>." >&2; exit 1; }

clusters=$(aws ecs list-clusters --query 'clusterArns[]' --output text | tr '\t' '\n')
[[ -n "$clusters" ]] || { echo "No ECS clusters in account $account ($AWS_REGION)." >&2; exit 1; }

# One line per service: "<service>\t<cluster arn>".
services=$(for c in $clusters; do
  aws ecs list-services --cluster "$c" --query 'serviceArns[]' --output text | tr '\t' '\n' \
    | awk -v c="$c" 'NF { n = split($0, p, "/"); print p[n] "\t" c }'
done | sort)

if [[ -z "$service" ]]; then
  [[ -n "$services" ]] || { echo "No ECS services in account $account." >&2; exit 1; }
  service=$(cut -f1 <<<"$services" | gum filter --header "ECS services in $account ($AWS_REGION)" \
    --placeholder "Type to filter") || exit 1
fi
cluster=$(awk -F'\t' -v s="$service" '$1 == s { print $2; exit }' <<<"$services")
[[ -n "$cluster" ]] || { echo "No service named $service in account $account." >&2; exit 1; }

caller=${TUIOS_WINDOW_ID:-}
target=()
[[ -n ${TUIOS_SESSION:-} ]] && target=(-s "$TUIOS_SESSION")
where=("${target[@]}")
if [[ -n "$caller" ]]; then
  workspace=$(tuios get-window "$caller" --json "${target[@]}" 2>/dev/null | jq -r '.workspace // empty')
  [[ -n "$workspace" ]] && where+=(--workspace "$workspace")
fi

# The event stream ends when the surface closes, by anyone; reading it is how
# this script waits.
coproc SHOW { tuios tml show "$here/watch-ecs-deployment.tml" --pane --events --json "${where[@]}"; }
exec {events}<&"${SHOW[0]}"
IFS= read -r opened <&"$events"
surface=$(jq -r '.surface // empty' <<<"$opened" 2>/dev/null)
[[ -n "$surface" ]] || { echo "Could not open the TML surface; run it from a tuios pane." >&2; exit 1; }

closed=false
cleanup() {
  local on="" off=""
  [[ -t 2 && -z ${NO_COLOR:-} ]] && on=$'\e[1;36m' off=$'\e[0m'
  printf 'rerun this with: mise run watch-ecs-deployment %s%q%s\n' "$on" "$service" "$off" >&2
  [[ $closed == true ]] || tuios tml close "$surface" >/dev/null 2>&1
  [[ $focus == true && -n "$caller" ]] && tuios focus-window "$caller" "${target[@]}" >/dev/null 2>&1
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Sleep up to $1 seconds, or with no argument until the pane closes; exit once it has.
wait_or_exit() {
  IFS= read -r ${1:+-t "$1"} -u "$events" _
  (($? > 128)) && return 0
  closed=true
  exit 0
}

[[ $focus == true ]] && tuios focus-window "$(jq -r .window_id <<<"$opened")" "${target[@]}" >/dev/null 2>&1
echo "Watching $service on ${cluster##*/} (surface $surface); ctrl+c here or in the pane stops it"

patch() {
  jq -c '[to_entries[] | {op: "replace", path: ("/" + .key), value: .value}]' <<<"$1" \
    | tuios tml patch "$surface" - >/dev/null
}

# jq helpers: ISO timestamps with an offset, as the CLI prints them, to epoch
# seconds; and epoch seconds to local clock time.
jq_lib='
  def epoch: if . == null then null else
    (.[0:19] + "Z" | fromdate) - ((.[-6:] | capture("(?<s>[+-])(?<h>\\d\\d):(?<m>\\d\\d)")
      | (if .s == "-" then -1 else 1 end) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60)) // 0)
  end;
  def clock: if . == null then "-" else localtime | strftime("%H:%M:%S") end;
  def dur: "\(. / 60 | floor)m \(. % 60 | floor)s";
'

declare -A revision_cache=()
history='[]'
while true; do
  deployment_arn=$(aws ecs list-service-deployments --cluster "$cluster" --service "$service" \
    --max-results 10 --output json \
    | jq -r '.serviceDeployments | sort_by(.createdAt) | last | .serviceDeploymentArn // empty')
  if [[ -z "$deployment_arn" ]]; then
    patch '{"status": "NONE", "statusLabel": "No service deployments in the last 90 days", "statusState": "idle"}'
    wait_or_exit
  fi
  deployment=$(aws ecs describe-service-deployments --service-deployment-arns "$deployment_arn" \
    --output json | jq -c '.serviceDeployments[0]') || { wait_or_exit "$poll"; continue; }

  target_arn=$(jq -r '.targetServiceRevision.arn' <<<"$deployment")
  if [[ -z "${revision_cache[$target_arn]:-}" ]]; then
    revision_cache[$target_arn]=$(aws ecs describe-service-revisions --service-revision-arns "$target_arn" \
      --output json | jq -c '.serviceRevisions[0] | {
        taskDef: (.taskDefinition | split("/")[-1]),
        images: ([.containerImages[]?.image | split("/")[-1]] | join(", "))
      }')
  fi
  events=$(aws ecs describe-services --cluster "$cluster" --services "$service" --output json \
    | jq -c '.services[0].events')

  state=$(jq -n -c --argjson d "$deployment" --argjson rev "${revision_cache[$target_arn]}" \
    --argjson events "$events" --argjson history "$history" \
    --arg service "$service" --arg cluster "${cluster##*/}" "$jq_lib"'
    ($d.startedAt // $d.createdAt | epoch) as $start
    | ($d.finishedAt // $d.stoppedAt | epoch) as $end
    | $d.status as $s
    | {
        service: $service,
        cluster: $cluster,
        status: $s,
        statusLabel: ({
          PENDING: "Deployment pending", IN_PROGRESS: "Rolling out",
          SUCCESSFUL: "Deployment succeeded", STOPPED: "Deployment stopped",
          STOP_REQUESTED: "Stop requested", ROLLBACK_REQUESTED: "Rollback requested",
          ROLLBACK_IN_PROGRESS: "Rolling back", ROLLBACK_SUCCESSFUL: "Rolled back",
          ROLLBACK_FAILED: "Rollback failed"
        }[$s] // $s),
        statusState: (if $s == "SUCCESSFUL" then "done"
          elif ($s | test("ROLLBACK|STOP")) then "errored" else "working" end),
        reason: ($d.statusReason // ""),
        started: ($start | clock),
        finished: ($end | clock),
        elapsed: ((($end // now) - $start) | dur),
        updated: (now | clock),
        requested: ($d.targetServiceRevision.requestedTaskCount // 0),
        running: ($d.targetServiceRevision.runningTaskCount // 0),
        pending: ($d.targetServiceRevision.pendingTaskCount // 0),
        oldRequested: ([$d.sourceServiceRevisions[]?.requestedTaskCount] | add // 0),
        oldRunning: ([$d.sourceServiceRevisions[]?.runningTaskCount] | add // 0),
        breaker: ($d.deploymentCircuitBreaker.status // "-"),
        breakerFailures: ($d.deploymentCircuitBreaker.failureCount // 0),
        breakerThreshold: ($d.deploymentCircuitBreaker.threshold // 0),
        rollback: (if $d.rollback then "\($d.rollback.reason // "") (from \($d.rollback.startedAt | epoch | clock))" else "" end),
        alarms: ($d.alarms.status // "-"),
        taskDef: $rev.taskDef,
        images: $rev.images,
        deploymentId: ($d.serviceDeploymentArn | split("/")[-1]),
        history: (($history + [$d.targetServiceRevision.runningTaskCount // 0])[-60:]),
        events: [$events[] | select((.createdAt | epoch) >= $start - 5)
          | {id, time: (.createdAt | epoch | clock), message}][:40],
        done: ($s | IN("SUCCESSFUL", "STOPPED", "ROLLBACK_SUCCESSFUL", "ROLLBACK_FAILED"))
      }') || { wait_or_exit "$poll"; continue; }

  history=$(jq -c '.history' <<<"$state")
  patch "$(jq -c 'del(.done)' <<<"$state")" || { closed=true; exit 0; }
  if [[ $(jq -r '.done' <<<"$state") == "true" ]]; then
    jq -r '"\(.statusLabel) after \(.elapsed); close the pane to exit."' <<<"$state"
    wait_or_exit
  fi
  wait_or_exit "$poll"
done
