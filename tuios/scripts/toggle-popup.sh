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
# state is kept. COMMAND starts in the folder of the pane the key was pressed
# in: the popup verb's cwd_from has the daemon read it from that pane's
# process, which follows a `cd` that the shell never reported. The pane itself
# reaches COMMAND as TUIOS_ACTIVE_PANE_ID, because the popup's own environment
# names the popup.
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

pane=${TUIOS_ACTIVE_PANE_ID:-${TUIOS_PANE_ID:-}}

# `tuios popup` has no flag for cwd_from, so the verb is called directly.
params=$(jq -n \
  --arg session "${TUIOS_SESSION:-}" --arg name "$name" \
  --arg width "$width" --arg height "$height" \
  --arg pane "$pane" --arg cwd "${TUIOS_ACTIVE_PANE_CWD:-$PWD}" \
  '{name: $name, width: $width, height: $height, cwd: $cwd,
    command: (["env", "TUIOS_ACTIVE_PANE_ID=\($pane)"] + $ARGS.positional)}
   + (if $session != "" then {session: $session} else {} end)
   + (if $pane != "" then {cwd_from: $pane} else {} end)' \
  --args -- "$@")
tuios call popup "$params" >/dev/null
