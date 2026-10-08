#!/usr/bin/env bash
# Herdr viewer tab for a Claude session's subagents, labelled after the
# session's pane, e.g. "Subagents · Fix login redirect".
#
#   (no argument)  SubagentStart: split a watch-subagents viewer for the new
#                  subagent into the session's tab, creating the tab if needed
#   end            SessionEnd: close the session's tab
#   resume         SessionStart on resume: reopen the tab with a viewer for
#                  each of the session's most recent subagents
#
# The viewer command reaches the new pane through HERDR_EXEC_CMD (see
# fish/conf.d/50-herdr-exec.fish) rather than `herdr pane run`, which races the
# shell's startup. The pane closes when the viewer is stopped with Ctrl-C.
#
# SubagentStart also fires when a subagent is resumed and on each message to an
# agent-team teammate, so agents that already have a viewer are skipped.
#
# Requires: jq, herdr, HERDR_ENV=1. Outside herdr the hook does nothing.

set -uo pipefail

[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] || exit 0

mode=${1:-start}
input=$(cat)
field() { jq -r --arg k "$1" '.[$k] // empty' <<<"$input"; }
session=$(field session_id)
cwd=$(field cwd)
main_transcript=$(field transcript_path)
[ -n "$session" ] || exit 0

root="${XDG_STATE_HOME:-$HOME/.local/state}/claude-subagent-viewer"
state="$root/$session"
# How many viewers a resumed session gets back, newest first.
REVIVE_MAX=6

herdr_json() { herdr "$@" 2>/dev/null; }
tab_alive() { [ -n "$1" ] && herdr_json tab get "$1" | jq -e '.result' >/dev/null; }

# The tab is named after the Claude pane's label, which herdr-automatic-rename
# keeps on the running command (`claude -r …`) until Claude sets its title.
pane_title() { herdr_json pane get "${HERDR_PANE_ID:-}" | jq -r '.result.pane.label // empty'; }
tab_label() {
  local title=$1
  case "$title" in claude | "claude "*) title="" ;; esac
  [ ${#title} -gt 40 ] && title="${title:0:39}…"
  echo "Subagents${title:+ · $title}"
}

if [ "$mode" = end ]; then
  tab=$(cat "$state/tab" 2>/dev/null)
  [ -n "$tab" ] && herdr tab close "$tab" >/dev/null 2>&1
  rm -f "$state/tab"
  # /clear starts a new session id, so this one can never be resumed into.
  [ "$(field reason)" = clear ] && rm -rf "$state"
  exit 0
fi

mkdir -p "$state"
# Sessions that were never resumed leave their state behind.
find "$root" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null

# Parallel subagents start their hooks together; without the lock two of them
# can both find no tab and create one each.
lock="$state/lock"
for _ in $(seq 100); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
trap 'rmdir "$lock" 2>/dev/null' EXIT

watcher="$HOME/.claude/skills/watch-subagents/watch-agent.sh"
colours=(36 35 33 32 34)
tab=$(cat "$state/tab" 2>/dev/null)
tab_alive "$tab" || tab=""
opened=0

# open_viewer <agent-id> <agent-type>
open_viewer() {
  local agent=$1 label=${2//\'/} colour exec_cmd created last direction pane
  colour=${colours[$((opened % ${#colours[@]}))]}
  exec_cmd="clear; bash '$watcher' '${main_transcript%.jsonl}/subagents/agent-${agent}.jsonl' '$label' $colour"
  if [ -z "$tab" ]; then
    created=$(herdr_json tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$cwd" \
      --label "$(tab_label "$(pane_title)")" --no-focus --env "HERDR_EXEC_CMD=$exec_cmd")
    tab=$(jq -r '.result.tab.tab_id // empty' <<<"$created")
    [ -n "$tab" ] || return 1
    echo "$tab" >"$state/tab"
  else
    last=$(herdr_json pane list --workspace "$HERDR_WORKSPACE_ID" |
      jq -r --arg t "$tab" '[.result.panes[] | select(.tab_id == $t)] | last | .pane_id // empty')
    [ -n "$last" ] || return 1
    # Alternate the direction so viewers tile instead of thinning into slivers.
    direction=$([ $((opened % 2)) -eq 1 ] && echo right || echo down)
    pane=$(herdr_json pane split --pane "$last" --direction "$direction" --cwd "$cwd" \
      --no-focus --env "HERDR_EXEC_CMD=$exec_cmd" | jq -r '.result.pane.pane_id // empty')
    [ -n "$pane" ] || return 1
  fi
  opened=$((opened + 1))
}

if [ "$mode" = resume ]; then
  [ -z "$tab" ] && [ -s "$state/agents" ] || exit 0
  tail -n "$REVIVE_MAX" "$state/agents" | while IFS=$'\t' read -r agent type; do
    open_viewer "$agent" "$type" || break
  done
  tab=$(cat "$state/tab" 2>/dev/null)
  [ -n "$tab" ] || exit 0
  # On resume the pane still shows the launch command; wait for Claude's title.
  for _ in $(seq 30); do
    title=$(pane_title)
    case "$title" in "" | claude | "claude "*) sleep 1 ;; *) break ;; esac
  done
  herdr tab rename "$tab" "$(tab_label "$title")" >/dev/null 2>&1
  exit 0
fi

agent=$(field agent_id)
[ -n "$agent" ] || exit 0
[ -n "$tab" ] && herdr tab rename "$tab" "$(tab_label "$(pane_title)")" >/dev/null 2>&1
grep -q "^$agent	" "$state/agents" 2>/dev/null && [ -n "$tab" ] && exit 0
opened=$(cat "$state/agents" 2>/dev/null | wc -l)
opened=${opened//[^0-9]/}
open_viewer "$agent" "$(field agent_type)" || exit 0
grep -q "^$agent	" "$state/agents" 2>/dev/null || printf '%s\t%s\n' "$agent" "$(field agent_type)" >>"$state/agents"
