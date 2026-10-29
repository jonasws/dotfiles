#!/usr/bin/env bash
# Jump to a pane for the `tuios-sessions` channel.
#
# Usage: tuios-focus.sh TOKEN   (<session>/<window id prefix>)
#
# Focus the pane first, then switch the client to its session: focusing is a
# daemon call that works on any session, and doing it first means the client
# arrives on the right pane instead of arriving and then moving.
set -euo pipefail

token="${1-}"
[[ "$token" =~ ^[^[:space:]/]+/[0-9a-f]+$ ]] || exit 0
session=${token%%/*} window=${token#*/}

tuios focus-window -s "$session" "$window" >/dev/null
if [[ "$session" != "${TUIOS_SESSION:-}" ]]; then
  tuios switch-session "$session" >/dev/null
fi
