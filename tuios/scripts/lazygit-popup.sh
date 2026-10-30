#!/usr/bin/env bash
# Lazygit for a tuios popup, on the panel named by $1 (status, branch, log,
# stash), in the repo of the pane the key was pressed in. Opened through
# toggle-popup.sh, which passes that pane as TUIOS_ACTIVE_PANE_CWD.
set -euo pipefail

dir=$(lazygit --print-config-dir)
cd "${TUIOS_ACTIVE_PANE_CWD:-$PWD}"
exec lazygit --use-config-file "$dir/config.yml,$dir/popup.yml" "$@"
