#!/usr/bin/env bash
# Toggle the tsk board: close it when it sits in the tab in view, otherwise let
# herdr-tsk open or focus it as usual. Custom commands get the tab the key was
# pressed in as HERDR_ACTIVE_TAB_ID.
set -euo pipefail

tab=${HERDR_ACTIVE_TAB_ID:-$(herdr pane list | jq -r '.result.panes[] | select(.focused) | .tab_id' | head -n1)}

board=$(herdr pane list |
  jq --arg tab "$tab" '.result.panes |= map(select(.tab_id == $tab))' |
  tsk --find-board-pane || true)

if [[ -n $board ]]; then
  herdr plugin pane close "$board" >/dev/null
else
  herdr plugin action invoke herdr-tsk.open-board >/dev/null
fi
