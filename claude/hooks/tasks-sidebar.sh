#!/usr/bin/env bash
# Claude Code hooks for the herdr taskbar (toggle-herdr-taskbar.sh).
#
#   session        SessionStart: name this session's task file for Claude
#   (no argument)  PostToolUse on Write|Edit|MultiEdit: show the taskbar when
#                  Claude writes the session's task file
#   end            SessionEnd: close the taskbar
#
# The task file is TASKS-<session-id>.md at the repo root, so parallel sessions
# and worktrees on one repo each keep their own list. TASKS-*.md is ignored in
# git/ignore.
#
# Requires: jq, herdr. Outside herdr only the session context is printed.

set -uo pipefail

mode=${1:-open}
input=$(cat)
field() { jq -r "$1 // empty" <<<"$input"; }
session=$(field .session_id)
cwd=$(field .cwd)
[ -n "$session" ] && [ -n "$cwd" ] || exit 0

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || (cd "$cwd" && pwd -P))
file="$root/TASKS-$session.md"
taskbar="$(dirname "${BASH_SOURCE[0]}")/toggle-herdr-taskbar.sh"

if [ "$mode" = session ]; then
  jq -n --arg f "$file" --arg s "$session" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
    "This session'"'"'s task file is \($f) (see Task lists in CLAUDE.md). Its frontmatter title is: Tasks for Claude session \($s)."}}'
  exit 0
fi

[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0

if [ "$mode" = end ]; then
  [ -n "${HERDR_TAB_ID:-}" ] && bash "$taskbar" close "$HERDR_TAB_ID"
  exit 0
fi

written=$(field .tool_input.file_path)
case "$written" in /*) ;; *) written="$cwd/$written" ;; esac
[ "${written##*/}" = "${file##*/}" ] || exit 0
[ "$(cd "${written%/*}" 2>/dev/null && pwd -P)" = "$root" ] || exit 0
bash "$taskbar" open "$HERDR_PANE_ID" "$file"
