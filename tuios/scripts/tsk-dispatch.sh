#!/usr/bin/env bash
# Hand the tsk task under the board cursor to a new Claude Code agent.
#
# Usage: tsk-dispatch.sh here|worktree   (a tuios command key, pressed on the
#                                          tsk board popup)
#
# tsk stays the backlog: title, notes, steps and the review/done rules in
# claude/CLAUDE.md. The run gets a tuios task card titled "T<n>: <title>",
# which the agents view's board (prefix+i, b) moves through plan, verify,
# review and shipped as the agent's plan, checks and pull request change.
#
#   here      `tuios start-agent` in the repo's folder; the card is claimed for
#             the new pane. The agent moves the tsk task itself.
#   worktree  `tuios fan 1` on a branch tsk/t<n>-<slug>. A worktree is a tsk
#             project of its own, so this script starts the task on the main
#             checkout's board and the prompt carries the notes.
#
# start-agent and fan wait until the agent is at its prompt, so the work runs
# in the background; a failure opens a small popup that says why.
set -euo pipefail

mode=${1:-here}
cwd=${TUIOS_ACTIVE_PANE_CWD:-$PWD}
session=${TUIOS_SESSION:-}

. "$(dirname "${BASH_SOURCE[0]}")/tsk-board.sh"

fail() {
  local msg
  msg=$(printf 'tsk-dispatch: %s' "$1")
  tuios popup --name tsk-dispatch --width 70 --height 8 -- \
    bash -c 'printf "%s\n\npress enter to close" "$1"; read -r _' _ "$msg" >/dev/null 2>&1 || true
  exit 1
}

# The card id. `task add` prints JSON where it can; otherwise the first word
# of its output with a digit in it is taken as the id. An empty id still
# starts the agent, without a card.
add_card() {
  local out id=
  if out=$(tuios task add ${session:+-s "$session"} --json -p - "$1" <<<"$2" 2>/dev/null); then
    id=$(jq -r '.id // .task.id // empty' <<<"$out" 2>/dev/null || true)
  elif out=$(tuios task add ${session:+-s "$session"} -p - "$1" <<<"$2" 2>/dev/null); then
    id=$(grep -oE '\b[[:alnum:]_-]*[0-9][[:alnum:]_-]*\b' <<<"$out" | head -1 || true)
  fi
  printf '%s' "$id"
}

dispatch() {
  local task json title notes repo slug prompt card

  task=$(tsk_find_task)
  [[ -n $task ]] || fail "no task selected on the tsk board"

  repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) ||
    fail "$cwd is not in a git repository"
  json=$(cd "$repo" && tsk list "$task" --json) || fail "tsk list $task failed"
  title=$(jq -r '.[0].title // ""' <<<"$json")
  notes=$(jq -r '.[0].notes // ""' <<<"$json")
  [[ -n $title ]] || fail "tsk has no task $task in $repo"

  case $mode in
    here)
      prompt="Pick up tsk task $task: $title. Read it with \`tsk list $task\` and follow the task board rules: start it, tick its steps as they land, and move it to review with one line on what to look at."
      ;;
    worktree)
      prompt="Work on tsk task $task: $title.

This is a git worktree, which is a tsk project of its own, so the task is not on this board. Do not add or move tsk tasks from here; the task is already started on the main checkout. When the work is ready, open a pull request and say what to look at.${notes:+

Notes from the task:
$notes}"
      ;;
    *) fail "usage: tsk-dispatch.sh here|worktree" ;;
  esac

  card=$(add_card "$task: $title" "$prompt")

  # The popup stays out of the way of the new agent.
  tuios close-window tsk-board >/dev/null 2>&1 || true

  if [[ $mode == here ]]; then
    tuios start-agent claude --name "$task" --cwd "$repo" --focus \
      ${session:+-s "$session"} ${card:+--task "$card"} --prompt "$prompt" >/dev/null 2>&1 ||
      fail "start-agent for $task did not get ready; look at its pane or the Inbox"
  else
    slug=$(tr '[:upper:]' '[:lower:]' <<<"$title" | tr -cs 'a-z0-9' '-' | cut -c1-32 | sed 's/^-*//; s/-*$//')
    (cd "$repo" && tsk status "$task" start >/dev/null 2>&1) || true
    tuios fan 1 --agent claude --repo "$repo" \
      --name "tsk/$(tr '[:upper:]' '[:lower:]' <<<"$task")${slug:+-$slug}" \
      ${card:+--task "$card"} "$prompt" >/dev/null 2>&1 ||
      fail "tuios fan for $task failed"
  fi
}

dispatch </dev/null >/dev/null 2>&1 &
disown
