#!/usr/bin/env bash
# Show the AWS run_script that an agent's permission prompt is asking about,
# read-only in nvim. run-script-guard.py saves each script it asks about as
# ~/.cache/claude/run-script/<pane id>.py; this opens the one for the pane the
# key was pressed in, or the newest one when that pane has none.
set -euo pipefail

dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude/run-script"
file="$dir/${TUIOS_ACTIVE_PANE_ID:-none}.py"
if [[ ! -f $file ]]; then
  file=$(ls -t "$dir"/*.py 2>/dev/null | head -n 1 || true)
fi
if [[ -z $file ]]; then
  echo "No run_script has asked for permission yet."
  read -rsn1 -p "Press any key to close."
  exit 0
fi

# -M: not modifiable, not writable. Diagnostics off so the python LSP does not
# decorate the boto3 snippet with warnings.
exec nvim -M \
  -c 'set filetype=python number' \
  -c 'lua vim.diagnostic.enable(false)' \
  "$file"
