#!/usr/bin/env bash
# Open a command in a popup, or close that popup when it is already open.
#
# Usage: toggle-popup.sh NAME [WIDTH HEIGHT] -- COMMAND [ARGS...]
#
# Bound to a tuios command key of type "shell". A popup of type "popup" cannot
# toggle itself: tuios has no per-key "close if open", and the chord only
# reaches the program in the popup when tuios does not take it first.
#
# The popup is found by NAME, which tuios accepts as a window target, so no
# state is kept. COMMAND gets the pane the key was pressed in as
# TUIOS_ACTIVE_PANE_ID and TUIOS_ACTIVE_PANE_CWD, because the popup's own
# environment names the popup. A herdr script starts with as-herdr.sh.
set -euo pipefail

name=${1:?usage: toggle-popup.sh NAME [WIDTH HEIGHT] -- COMMAND...}
shift
width=90% height=80%
if [[ ${1:-} != -- ]]; then
  width=${1:?}; height=${2:?}
  shift 2
fi
shift

if tuios close-window "$name" >/dev/null 2>&1; then
  exit 0
fi

exec tuios popup --name "$name" --width "$width" --height "$height" -- \
  env \
    TUIOS_ACTIVE_PANE_ID="${TUIOS_ACTIVE_PANE_ID:-${TUIOS_PANE_ID:-}}" \
    TUIOS_ACTIVE_PANE_CWD="${TUIOS_ACTIVE_PANE_CWD:-$PWD}" \
    "$@"
