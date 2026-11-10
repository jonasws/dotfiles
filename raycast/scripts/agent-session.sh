#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Agent Session
# @raycast.mode compact
# @raycast.packageName Agents

# Optional parameters:
# @raycast.icon 🤖
# @raycast.argument1 { "type": "text", "placeholder": "words in title, repo or branch", "optional": true }
# @raycast.argument2 { "type": "dropdown", "placeholder": "Do", "optional": true, "data": [{"title": "Open", "value": "open"}, {"title": "Fork", "value": "fork"}, {"title": "Copy id", "value": "id"}, {"title": "Copy dir", "value": "cwd"}, {"title": "Copy transcript", "value": "transcript"}, {"title": "Copy pane", "value": "pane"}, {"title": "Copy resume command", "value": "resume"}] }

# @raycast.description Jump back into the newest coding-agent session that matches, in tuios.

# Opens through the same CLI as the agent-sessions television channel: the
# pane already running the session gets the focus, otherwise the session is
# resumed in a new pane of its repository's tuios session. Raycast runs this
# outside every pane, so AGENT_SESSIONS_TUIOS tells the CLI to use tuios anyway.
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cli="$HOME/.config/television/scripts/agent-sessions/agent-sessions.nu"

# /bin/bash is 3.2 here: an empty array under `set -u` is an error, so the
# words go unquoted and split on purpose.
# shellcheck disable=SC2086
key=$("$cli" find ${1-} 2>&1) || { echo "$key"; exit 1; }
title=$("$cli" get "$key" title)

case ${2:-open} in
  open)
    AGENT_SESSIONS_TUIOS=1 "$cli" open "$key" >/dev/null
    open -a Ghostty
    echo "Opened $title"
    ;;
  fork)
    AGENT_SESSIONS_TUIOS=1 "$cli" open --fork "$key" >/dev/null
    open -a Ghostty
    echo "Forked $title"
    ;;
  *)
    "$cli" get "$key" "$2" | pbcopy
    echo "Copied $2 of $title"
    ;;
esac
