#!/usr/bin/env bash
# Herdr "right sidebar" for Claude Code task lists: a split taking 30% of the
# tab, rendering the session's TASKS-<session-id>.md with mdcat, unwrapped.
#
#   toggle [pane]        hide or show the taskbar in the pane's tab; the pane
#                        defaults to the calling pane, else the focused one
#   open <pane> <file>   show <file> beside <pane>, unless the tab already has
#                        a taskbar or the user hid it there
#   close <tab>          close the tab's taskbar
#   view <file>          runs inside the taskbar: <file> rendered by mdcat in less
#
# The taskbar is the tab's pane labelled "Tasks". Hiding it marks the tab, so
# Claude's next edit does not bring it straight back; showing it clears the mark.
#
# Herdr has no right-hand sidebar or plugin sidebar placement (herdr#4115 and
# herdr#4312, both not planned), so this is an ordinary split pane.
#
# Bound to prefix+t in herdr/config.toml and to /taskbar in Claude Code.
#
# Requires: jq, herdr, mdcat, less.

set -uo pipefail

LABEL=Tasks
# The original pane's share of the split.
RATIO=0.7
state="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-taskbar"
hidden="$state/hidden"

view() {
  # Unwrapped, so every task is one line, and shown in less -S so long ones
  # scroll sideways. mdcat --watch can only draw straight to the terminal, so
  # a background loop re-renders on change and sends less R, which rereads the
  # file in place, then scrolls to the current task.
  local file=$1 out sum last="" watcher
  out=$(mktemp "${TMPDIR:-/tmp}/herdr-taskbar.XXXXXX")
  # The first unchecked item is the task in progress (see Task lists in
  # CLAUDE.md). It gets Catppuccin surface1 as background, re-applied after
  # each of mdcat's resets inside the line so the highlight spans all of it.
  render() {
    mdcat --ansi --columns 0 --emoji --local --image-protocol none "$file" 2>/dev/null |
      perl -pe 'BEGIN { $hl = "\e[48;2;69;71;90m\e[1m" }
        if (!$done && /\[ \]/) { s/\e\[0?m/$&$hl/g; $_ = "$hl$_"; s/\n?$/\e[0m\n/; $done = 1 }' >"$out"
  }
  # Line to scroll to: the current task, with a few lines of context above it.
  current_line() {
    local n
    n=$(grep -n '\[ \]' "$out" | head -1 | cut -d: -f1)
    echo $((${n:-1} > 4 ? n - 3 : 1))
  }
  render
  (
    while sleep 1; do
      sum=$(cksum <"$file" 2>/dev/null)
      [ -z "$last" ] && { last=$sum; continue; }
      [ "$sum" = "$last" ] && continue
      last=$sum
      render
      # <n>g follows the highlight to the new task, then R rereads the file.
      # In that order because less drops input that arrives right after R.
      herdr pane send-text "$HERDR_PANE_ID" "$(current_line)gR" >/dev/null 2>&1
    done
  ) &
  watcher=$!
  trap 'kill "$watcher" 2>/dev/null; rm -f "$out"' EXIT
  less -RS -~ --mouse --shift 8 --prompt='?e(end):%pb\%.' "$out"
}

# taskbar_in <tab>: pane id of the tab's taskbar, if it has one
taskbar_in() {
  herdr pane list 2>/dev/null |
    jq -r --arg t "$1" --arg l "$LABEL" \
      '[.result.panes[] | select(.tab_id == $t and .label == $l)][0].pane_id // empty'
}

tab_of() { herdr pane get "$1" 2>/dev/null | jq -r '.result.pane.tab_id // empty'; }

repo_root() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || (cd "$1" && pwd -P); }

# task_file <pane>: the pane's Claude session file, else the newest task file
# in its repo
task_file() {
  local pane root session newest
  pane=$(herdr pane get "$1" 2>/dev/null) || return 1
  root=$(repo_root "$(jq -r '.result.pane.cwd' <<<"$pane")")
  session=$(jq -r 'select(.result.pane.agent == "claude") | .result.pane.agent_session.value // empty' <<<"$pane")
  if [ -n "$session" ] && [ -f "$root/TASKS-$session.md" ]; then
    echo "$root/TASKS-$session.md"
    return
  fi
  newest=$(ls -t "$root"/TASKS-*.md 2>/dev/null | head -1)
  [ -n "$newest" ] && echo "$newest"
}

# split_beside <pane> <file>
split_beside() {
  local pane
  pane=$(herdr pane split --pane "$1" --direction right --ratio "$RATIO" \
    --cwd "${2%/*}" --no-focus \
    --env "HERDR_EXEC_CMD=bash '${BASH_SOURCE[0]}' view '$2'" 2>/dev/null |
    jq -r '.result.pane.pane_id // empty')
  [ -n "$pane" ] && herdr pane rename "$pane" "$LABEL" >/dev/null 2>&1
}

with_lock() {
  local lock="$state/$1.lock" rc
  mkdir -p "$state"
  # Parallel edits fire their hooks together; without the lock both can find
  # no taskbar and open one each.
  for _ in $(seq 50); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
  shift
  "$@"
  rc=$?
  rmdir "$lock" 2>/dev/null
  return $rc
}

open_unless_present() {
  local tab=$1 pane=$2 file=$3
  [ -e "$hidden/$tab" ] && return 0
  [ -n "$(taskbar_in "$tab")" ] && return 0
  split_beside "$pane" "$file"
}

toggle() {
  local pane=$1 tab taskbar file
  tab=$(tab_of "$pane")
  [ -n "$tab" ] || return 1
  mkdir -p "$hidden"
  find "$hidden" -type f -mtime +14 -delete 2>/dev/null
  taskbar=$(taskbar_in "$tab")
  if [ -n "$taskbar" ]; then
    herdr pane close "$taskbar" >/dev/null 2>&1
    touch "$hidden/$tab"
    echo "Taskbar hidden."
    return
  fi
  rm -f "$hidden/$tab"
  file=$(task_file "$pane")
  if [ -z "$file" ]; then
    echo "No TASKS-*.md in this repo yet."
    return
  fi
  split_beside "$pane" "$file"
  echo "Taskbar showing ${file##*/}."
}

case "${1:-}" in
view) view "$2" ;;
toggle)
  pane=${2:-${HERDR_PANE_ID:-$(herdr pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty')}}
  [ -n "$pane" ] || exit 0
  toggle "$pane"
  ;;
open)
  tab=$(tab_of "$2")
  [ -n "$tab" ] || exit 0
  with_lock "$tab" open_unless_present "$tab" "$2" "$3"
  ;;
close)
  taskbar=$(taskbar_in "$2")
  [ -n "$taskbar" ] && herdr pane close "$taskbar" >/dev/null 2>&1
  rm -f "$hidden/$2"
  ;;
*)
  echo "usage: ${0##*/} toggle [pane] | open <pane> <file> | close <tab> | view <file>" >&2
  exit 2
  ;;
esac
