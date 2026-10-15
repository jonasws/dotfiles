#!/usr/bin/env bash
# Lazygit for a Herdr popup, on the panel named by $1 (status, branch, log,
# stash), in the repo of the pane the key was pressed in.
set -euo pipefail

dir=$(lazygit --print-config-dir)
cd "${HERDR_ACTIVE_PANE_CWD:-$PWD}"
exec lazygit --use-config-file "$dir/config.yml,$dir/popup.yml" "$@"
