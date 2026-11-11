#!/usr/bin/env bash
# The agent-sessions picker as a popup, bound to Cmd+O in tuios and herdr.
#
#   tuios: a "shell" command key runs this outside every pane; it toggles a
#          popup named agent-sessions that runs this script again with
#          --inside, and closes the popup when the focus leaves it.
#   herdr: a "popup" command key runs this inside the popup it opened.
#
# Either way the picker starts in the directory of the pane the key was
# pressed in, so its "here" scope is that pane's repository. toggle-popup.sh
# starts the tuios popup there; herdr passes HERDR_ACTIVE_PANE_CWD.
set -euo pipefail

self=$(realpath "$0")
tuios_scripts=~/.config/tuios/scripts

if [[ ${1-} == --inside ]]; then
  exec "$tuios_scripts/close-on-leave.sh" tv agent-sessions
fi

if [[ -n ${TUIOS_ACTIVE_PANE_ID:-} || ${TUIOS_ENV:-} == 1 ]]; then
  exec "$tuios_scripts/toggle-popup.sh" agent-sessions 90% 80% -- "$self" --inside
fi

cd "${HERDR_ACTIVE_PANE_CWD:-$PWD}"
exec tv agent-sessions
