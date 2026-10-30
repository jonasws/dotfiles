#!/usr/bin/env bash
# Run a picker in a popup and close the popup when the person navigates away
# from it without picking: focus moves to another pane (a click, a focus key),
# the workspace changes, or the client leaves the session.
#
# Usage: close-on-leave.sh COMMAND [ARGS...]   (inside a popup)
#
# The popup is only closed while COMMAND itself still runs. A tv action in
# `execute` mode replaces tv with a script that focuses a pane or switches
# session, which moves the focus away too; closing the popup then would kill
# that script halfway.
set -euo pipefail

win=${TUIOS_PANE_ID:?close-on-leave.sh runs inside a tuios popup}
session=${TUIOS_SESSION:?}
pid=$$
prog=${1##*/}

watch() {
  tuios subscribe -s "$session" \
    --types window-focused,workspace-switched,client-session-changed,window-closed |
    jq --unbuffered -r --arg w "$win" --arg s "$session" '
      if .type == "window-closed" and .window == $w then "closed"
      elif .type == "window-focused" and .window != $w then "left"
      elif .type == "workspace-switched" then "left"
      elif .type == "client-session-changed" and .session == $s and .attached == false then "left"
      else empty end' |
    while read -r what; do
      if [[ $what == left ]]; then
        comm=$(ps -o comm= -p "$pid" 2>/dev/null) || exit 0
        [[ ${comm##*/} == "$prog" ]] && tuios close-window -s "$session" "$win" >/dev/null 2>&1
      fi
      exit 0
    done
}

watch </dev/null >/dev/null 2>&1 &
exec "$@"
