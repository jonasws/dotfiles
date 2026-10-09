#!/usr/bin/env bash
# SessionStart: tell Claude what is live on the tsk board for this repo, so a
# new session picks up started, blocked and review work without being asked.
#
# tsk scopes a project to the git root, so each worktree would be a separate
# project. Inside a linked worktree this names the main checkout instead, and
# tells Claude to pass it as -p so every worktree shares one project.
#
# Silent outside git, when tsk is missing, or when nothing is live.
#
# Requires: tsk, jq, git.

set -uo pipefail

command -v tsk >/dev/null || exit 0
cwd=$(jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
toplevel=$(git rev-parse --show-toplevel)
project=${common%/.git}
scope=""
[ "$project" != "$toplevel" ] && [ -d "$project" ] &&
  scope="This is a git worktree of $project. Pass -p $project to every tsk add and list so tasks land in the main repo's project. "

summary=$(tsk list -p "$project" --json 2>/dev/null | jq -r '
  map(select(.status != "done" and .status != "open"))
  | sort_by({blocked: 0, review: 1, started: 2, ready: 3}[.status] // 9)
  | .[:8][] | "- T\(.number) [\(.status)] \(.title)"' 2>/dev/null)
[ -n "$summary$scope" ] || exit 0

jq -n --arg scope "$scope" --arg s "$summary" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
  ("tsk board (see Task board in CLAUDE.md). \($scope)" + (if $s == "" then "No live tasks in this project." else "Live tasks in this project:\n\($s)" end))}}'
