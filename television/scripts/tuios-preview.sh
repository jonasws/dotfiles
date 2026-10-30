#!/usr/bin/env bash
# Preview a pane for the `tuios-sessions` channel.
#
# Usage: tuios-preview.sh TOKEN MODE
#   TOKEN  <session>/<window id prefix>, the first word of a channel row
#   MODE   screen      the pane as drawn, colours kept
#          scrollback  the pane's history, unwrapped, colours kept
#          summary     what the agent is doing: the prompt it waits on, or the
#                      recap of its turn and its latest activity; the screen
#                      when the pane has no agent hooks
#          log         the agent's activity log, newest first
#
# The previewer kills a job after 3s, so each mode is one or two tuios calls.
set -uo pipefail

token="${1-}" mode="${2:-screen}"
if [[ ! "$token" =~ ^[^[:space:]/]+/[0-9a-f]+$ ]]; then
  echo "No panes in this scope"
  exit 0
fi
session=${token%%/*} window=${token#*/}

screen() { tuios capture-pane -s "$session" -w "$window" --ansi --trim 2>&1; }

# agent-log prints plain text. The default highlighters split paths and
# numbers into confetti, so only the time and the entry kinds and states are
# coloured. A keyword is coloured wherever it appears, including in the
# agent's own words.
paint() {
  command -v tspin >/dev/null || { cat; return; }
  tspin -p --disable paths,numbers,quotes,uuids,key-value-pairs,urls,durations \
    --highlight cyan:prompt \
    --highlight green:said,done \
    --highlight yellow:tool,working \
    --highlight magenta:state \
    --highlight blue:subagent \
    --highlight red:failed,needs_input,errored
}

case $mode in
  screen) screen ;;
  scrollback) tuios capture-pane -s "$session" -w "$window" -S --lines 400 --unwrap --ansi --trim 2>&1 ;;
  log) tuios agent-log -s "$session" -w "$window" --limit 64 2>&1 | tail -r | paint || screen ;;
  summary)
    state=$(tuios get-agent-state -s "$session" -w "$window" 2>/dev/null | tr -d '[:space:]')
    if [[ $state == *needs_input* ]] && tuios peek-prompt -s "$session" -w "$window" 2>/dev/null; then
      exit 0
    fi
    if recap=$(tuios agent-log -s "$session" -w "$window" --recap 2>/dev/null) && [[ -n $recap ]]; then
      {
        printf '%s\n\n' "$recap"
        tuios agent-log -s "$session" -w "$window" --limit 12 2>/dev/null
      } | paint
    else
      screen
    fi
    ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
