#!/usr/bin/env bash
# Edit a tsk task's notes in $EDITOR. Without an argument it edits the task
# under the tsk board cursor, for a tuios popup. The board has no API for its
# selection, so the task number is read off the screen: a board row carries the
# `▸` cursor marker, and a task page opens with its `T<n>` header.
set -euo pipefail

fail() {
  printf 'tsk-notes: %s\n\npress enter to close' "$1"
  read -r _
  exit 1
}

selected_task() {
  local screen header task
  screen=$(tuios capture-pane -w "$1") || return 0
  task=$(rg -m1 -o '▸.*?\b(T\d+)\b' -r '$1' <<<"$screen" || true)
  if [[ -z $task ]]; then
    header=$(awk 'NF { print; exit }' <<<"$screen")
    task=$(rg -o '^\s*\S+\s+(T\d+)\b' -r '$1' <<<"$header" || true)
  fi
  printf '%s' "$task"
}

# toggle-popup.sh passes the pane the key was pressed in as
# TUIOS_ACTIVE_PANE_ID; prefer it so the board in view wins when several are
# open.
task=${1:-}
if [[ -z $task && -n ${TUIOS_ACTIVE_PANE_ID:-} ]]; then
  task=$(selected_task "$TUIOS_ACTIVE_PANE_ID")
fi
if [[ -z $task ]]; then
  pane=$(tuios list-windows --json |
    jq -r 'first(.windows[] | select(.foreground_cmd == "tsk") | .window_id) // empty')
  [[ -n $pane ]] || fail "no tsk board pane in this session"
  task=$(selected_task "$pane")
fi
[[ -n $task ]] || fail "no task selected on the board"

dir=$(mktemp -d)
tmp=$dir/$task.md
trap 'rm -rf "$dir"' EXIT

tsk list "$task" --json | jq -r '.[0].notes // ""' >"$tmp"
before=$(shasum <"$tmp")
"${EDITOR:-nvim}" "$tmp"
[[ $(shasum <"$tmp") != "$before" ]] || exit 0

if ! tsk edit "$task" --notes="$(<"$tmp")" >/dev/null; then
  trap - EXIT
  fail "tsk edit $task failed; your edit is kept in $tmp"
fi
