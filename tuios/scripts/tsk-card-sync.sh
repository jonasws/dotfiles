#!/usr/bin/env bash
# Move a tsk task to review when the tuios task card that runs it reaches
# review, so the board shows work an agent has handed back. Cards are titled
# "T<n>: <title>" by tsk-dispatch.sh; other cards are ignored.
#
# Only a task in started moves. Done stays the user's, and a task the user sent
# back is not moved again for the same card stage: each card stage is handled
# once, keyed by session, card id and stage_at, in $state/handled.
#
# Runs under launchd (tuios/launchd/com.jonasws.tsk-card-sync.plist), which
# gives it no PATH. TSK_CARD_SYNC_DRY=1 logs what it would do and writes
# nothing. Log: ~/.local/state/tsk-card-sync/sync.log
set -uo pipefail

PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:/opt/homebrew/bin:$PATH"
export PATH
# The mise shims read the config of the folder they run in; / has none.
cd /

state=${XDG_STATE_HOME:-$HOME/.local/state}/tsk-card-sync
handled=$state/handled
mkdir -p "$state"
touch "$handled"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

# One card in review: session, card id, title, stage_at.
sync_card() {
  local session=$1 id=$2 title=$3 stage_at=$4 key n status pr text
  [[ $title =~ ^T([0-9]+): ]] || return 0
  n=${BASH_REMATCH[1]}
  key="$session $id $stage_at"
  grep -qxF "$key" "$handled" && return 0

  status=$(tsk list "T$n" --json 2>/dev/null | jq -r '.[0].status // empty')
  if [[ $status != started ]]; then
    log "T$n is ${status:-not on the board}; card $session/$id left alone"
  else
    pr=$(tuios task attachments "$id" -s "$session" --json 2>/dev/null |
      jq -r '[.attachments[]? | select(.kind == "pr") | .url][-1] // empty')
    text="The agent handed it back on tuios card $session/$id${pr:+: $pr}"
    if [[ ${TSK_CARD_SYNC_DRY:-} == 1 ]]; then
      log "dry run: tsk status T$n review --done '$text'"
      return 0
    fi
    if tsk status "T$n" review --done "$text" >/dev/null 2>&1; then
      log "T$n -> review ($session/$id${pr:+, $pr})"
    else
      log "T$n: tsk status review refused; will not retry this card stage"
    fi
  fi
  printf '%s\n' "$key" >>"$handled"
}

# Every card in review now, for a start and after a gap in the stream.
reconcile() {
  tuios task ls --all-sessions --stage review --json 2>/dev/null |
    jq -r '.tasks[]? | [.session, .id, .title, (.stage_at | tostring)] | @tsv' |
    while IFS=$'\t' read -r session id title stage_at; do
      sync_card "$session" "$id" "$title" "$stage_at"
    done
}

while :; do
  reconcile
  tuios subscribe --types task-changed 2>/dev/null |
    jq --unbuffered -r '
      if .type == "gap" then "gap"
      elif .type == "task-changed" and .action == "staged" and .task.stage == "review"
      then ["card", .task.session, .task.id, .task.title, (.task.stage_at | tostring)] | @tsv
      else empty end' |
    while IFS=$'\t' read -r kind session id title stage_at; do
      case $kind in
        gap) reconcile ;;
        card) sync_card "$session" "$id" "$title" "$stage_at" ;;
      esac
    done
  # The daemon stopped or restarted: wait, then catch up from the card list.
  sleep 10
done
