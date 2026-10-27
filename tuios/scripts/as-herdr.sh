#!/usr/bin/env bash
# Run a script written for a herdr command key from a tuios command key.
#
# herdr hands its keys HERDR_ACTIVE_PANE_ID, HERDR_ACTIVE_TAB_ID and
# HERDR_ACTIVE_PANE_CWD. tuios hands its keys TUIOS_ACTIVE_PANE_ID (a window
# UUID), TUIOS_ACTIVE_PANE_CWD and TUIOS_SOCKET. tuios answers herdr's socket
# API on its own socket plus `.herdr`, where a pane id reads
# w<session>:p<first 12 hex digits of the window UUID>.
set -euo pipefail

export HERDR_ENV=1
# Always tuios's socket: a tuios started from a herdr pane inherits herdr's.
export HERDR_SOCKET_PATH=${TUIOS_SOCKET:?not run from a tuios command key}.herdr
unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID
export HERDR_ACTIVE_PANE_CWD=${TUIOS_ACTIVE_PANE_CWD:-$PWD}

if [[ -n ${TUIOS_ACTIVE_PANE_ID:-} ]]; then
  suffix=":p$(tr -d - <<<"$TUIOS_ACTIVE_PANE_ID" | cut -c1-12)"
  pane=$(herdr pane list |
    jq -c --arg s "$suffix" 'first(.result.panes[] | select(.pane_id | endswith($s))) // empty')
  if [[ -n $pane ]]; then
    HERDR_ACTIVE_PANE_ID=$(jq -r .pane_id <<<"$pane")
    HERDR_ACTIVE_TAB_ID=$(jq -r .tab_id <<<"$pane")
    export HERDR_ACTIVE_PANE_ID HERDR_ACTIVE_TAB_ID
  fi
fi

exec "$@"
