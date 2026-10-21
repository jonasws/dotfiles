#!/usr/bin/env bash
# Herdr viewer tab for a Claude session's subagents, labelled after the
# session's pane, e.g. "Subagents · Fix login redirect". The tab opens only on
# demand; the hooks just record which subagents a session has run.
#
#   (no argument)  SubagentStart: record the subagent, and add a viewer for it
#                  when the session's tab is open
#   resume         SessionStart on resume: record the session's new pane
#   end            SessionEnd: close the session's tab
#   toggle         herdr key (prefix+shift+s): inside a viewer tab, close it;
#                  in a Claude pane, focus its tab or open one with a viewer
#                  for each of the session's most recent subagents
#
# The viewer command reaches the new pane through HERDR_EXEC_CMD (see
# fish/conf.d/50-herdr-exec.fish) rather than `herdr pane run`, which races the
# shell's startup. The pane closes when the viewer is stopped with Ctrl-C.
#
# SubagentStart also fires when a subagent is resumed and on each message to an
# agent-team teammate, so agents that already have a viewer are skipped.
#
# Requires: jq, herdr. Outside herdr the hook does nothing.

set -uo pipefail

# Key commands run outside any pane: they get HERDR_SOCKET_PATH but no HERDR_ENV.
[ "${HERDR_ENV:-}" = 1 ] || [ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0

mode=${1:-start}
root="${XDG_STATE_HOME:-$HOME/.local/state}/claude-subagent-viewer"
# How many viewers the toggle opens, newest first.
REVIVE_MAX=6

herdr_json() { herdr "$@" 2>/dev/null; }
tab_alive() { [ -n "$1" ] && herdr_json tab get "$1" | jq -e '.result' >/dev/null; }
notify() { herdr notification show "$1" --sound none >/dev/null 2>&1; }

# The tab is named after the Claude pane's label, which herdr-automatic-rename
# keeps on the running command (`claude -r …`) until Claude sets its title.
pane_title() { herdr_json pane get "$pane" | jq -r '.result.pane.label // empty'; }
tab_label() {
  local title=$1
  case "$title" in claude | "claude "*) title="" ;; esac
  [ ${#title} -gt 40 ] && title="${title:0:39}…"
  echo "Subagents${title:+ · $title}"
}

# Hooks name the session on stdin; the toggle finds it from the pane it was
# pressed in, through what the hooks recorded.
if [ "$mode" = toggle ]; then
  active_pane=${HERDR_ACTIVE_PANE_ID:-$(herdr_json pane list | jq -r '.result.panes[] | select(.focused) | .pane_id' | head -n1)}
  active_tab=${HERDR_ACTIVE_TAB_ID:-$(herdr_json pane get "$active_pane" | jq -r '.result.pane.tab_id // empty')}
  viewer_of=$(grep -lxF -- "$active_tab" "$root"/*/tab 2>/dev/null | head -n1)
  if [ -n "$viewer_of" ]; then
    herdr tab close "$active_tab" >/dev/null 2>&1
    rm -f "$viewer_of" "${viewer_of%/tab}/shown"
    exit 0
  fi
  pane_file=$(grep -lxF -- "$active_pane" "$root"/*/pane 2>/dev/null | xargs ls -t 2>/dev/null | head -n1)
  [ -n "$pane_file" ] || { notify "No subagents recorded for this pane"; exit 0; }
  state=${pane_file%/pane}
else
  input=$(cat)
  field() { jq -r --arg k "$1" '.[$k] // empty' <<<"$input"; }
  session=$(field session_id)
  [ -n "$session" ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] || exit 0
  state="$root/$session"

  if [ "$mode" = end ]; then
    tab=$(cat "$state/tab" 2>/dev/null)
    [ -n "$tab" ] && herdr tab close "$tab" >/dev/null 2>&1
    rm -f "$state/tab" "$state/shown"
    # /clear starts a new session id, so this one can never be resumed into.
    [ "$(field reason)" = clear ] && rm -rf "$state"
    exit 0
  fi

  mkdir -p "$state"
  # Sessions that were never resumed leave their state behind.
  find "$root" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null
  echo "${HERDR_PANE_ID:-}" >"$state/pane"
  echo "$HERDR_WORKSPACE_ID" >"$state/workspace"
  field cwd >"$state/cwd"
  field transcript_path >"$state/transcript"
  [ "$mode" = resume ] && exit 0
fi

pane=$(cat "$state/pane" 2>/dev/null)
workspace=$(cat "$state/workspace" 2>/dev/null)
cwd=$(cat "$state/cwd" 2>/dev/null)
main_transcript=$(cat "$state/transcript" 2>/dev/null)

# Parallel subagents start their hooks together; without the lock two of them
# can both find no tab and create one each.
lock="$state/lock"
for _ in $(seq 100); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
trap 'rmdir "$lock" 2>/dev/null' EXIT

watcher="$HOME/.claude/skills/watch-subagents/watch-agent.sh"
colours=(36 35 33 32 34)
tab=$(cat "$state/tab" 2>/dev/null)
tab_alive "$tab" || { tab=""; rm -f "$state/tab" "$state/shown"; }
opened=0

# open_viewer <agent-id> <agent-type>
open_viewer() {
  local agent=$1 label=${2//\'/} colour exec_cmd created last direction new_pane
  colour=${colours[$((opened % ${#colours[@]}))]}
  exec_cmd="clear; bash '$watcher' '${main_transcript%.jsonl}/subagents/agent-${agent}.jsonl' '$label' $colour"
  if [ -z "$tab" ]; then
    created=$(herdr_json tab create --workspace "$workspace" --cwd "$cwd" \
      --label "$(tab_label "$(pane_title)")" --no-focus --env "HERDR_EXEC_CMD=$exec_cmd")
    tab=$(jq -r '.result.tab.tab_id // empty' <<<"$created")
    [ -n "$tab" ] || return 1
    echo "$tab" >"$state/tab"
    : >"$state/shown"
  else
    last=$(herdr_json pane list --workspace "$workspace" |
      jq -r --arg t "$tab" '[.result.panes[] | select(.tab_id == $t)] | last | .pane_id // empty')
    [ -n "$last" ] || return 1
    # Alternate the direction so viewers tile instead of thinning into slivers.
    direction=$([ $((opened % 2)) -eq 1 ] && echo right || echo down)
    new_pane=$(herdr_json pane split --pane "$last" --direction "$direction" --cwd "$cwd" \
      --no-focus --env "HERDR_EXEC_CMD=$exec_cmd" | jq -r '.result.pane.pane_id // empty')
    [ -n "$new_pane" ] || return 1
  fi
  printf '%s\n' "$agent" >>"$state/shown"
  opened=$((opened + 1))
}

if [ "$mode" = toggle ]; then
  if [ -z "$tab" ]; then
    [ -s "$state/agents" ] || { notify "No subagents in this session yet"; exit 0; }
    while IFS=$'\t' read -r agent type; do
      open_viewer "$agent" "$type" || break
    done < <(tail -n "$REVIVE_MAX" "$state/agents")
  fi
  [ -n "$tab" ] && herdr tab focus "$tab" >/dev/null 2>&1
  exit 0
fi

agent=$(field agent_id)
[ -n "$agent" ] || exit 0
grep -q "^$agent	" "$state/agents" 2>/dev/null || printf '%s\t%s\n' "$agent" "$(field agent_type)" >>"$state/agents"
[ -n "$tab" ] || exit 0
herdr tab rename "$tab" "$(tab_label "$(pane_title)")" >/dev/null 2>&1
grep -qxF "$agent" "$state/shown" 2>/dev/null && exit 0
opened=$(herdr_json pane list --workspace "$workspace" | jq --arg t "$tab" '[.result.panes[] | select(.tab_id == $t)] | length')
open_viewer "$agent" "$(field agent_type)"
