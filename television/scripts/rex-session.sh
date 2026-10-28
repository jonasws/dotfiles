#!/usr/bin/env bash
# Open a repository as a Rex session, or switch to it if one is already open.
#
# Rex sessions carry no cwd, so a session counts as the repo's when its label is
# the repo's directory name -- the label this script gives the ones it creates.
# Switching is a client action, so it goes through `rex do` rather than a plain
# subcommand.
set -euo pipefail

repo_path="${1:?usage: rex-session.sh <repo_path>}"
label="${repo_path##*/}"

session_id=$(
  rex session list --json |
    jq -r --arg label "$label" '.sessions[] | select(.label == $label) | .session_id' |
    head -n1
)

if [[ -z $session_id ]]; then
  session_id=$(rex new "$label" --cwd "$repo_path" --json | jq -r '.session_id')
fi

SESSION_ID="$session_id" rex do -e '
  local id = os.getenv("SESSION_ID")
  local view = rex.session.view({ session_id = id })
  rex.client.queue("session.select", { session_id = id, window_id = view and view.active_window_id })
' >/dev/null
