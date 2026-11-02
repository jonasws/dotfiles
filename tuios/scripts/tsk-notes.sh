#!/usr/bin/env bash
# Edit a tsk task's notes in $EDITOR. Without an argument it edits the task
# under the tsk board cursor (scripts/tsk-board.sh), for a tuios popup.
set -euo pipefail

fail() {
  printf 'tsk-notes: %s\n\npress enter to close' "$1"
  read -r _
  exit 1
}

. "$(dirname "${BASH_SOURCE[0]}")/tsk-board.sh"

task=${1:-}
if [[ -z $task ]]; then
  rc=0
  task=$(tsk_find_task) || rc=$?
  ((rc != 2)) || fail "no tsk board pane in this session"
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
