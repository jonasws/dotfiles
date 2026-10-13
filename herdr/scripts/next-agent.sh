#!/usr/bin/env bash
# Focus the next agent that needs attention: blocked first, then done (finished
# but not yet looked at), else simply the next agent. Order follows the sidebar
# with agent_panel_sort = "spaces", and each tier is walked from the focused
# agent onwards, so repeated presses cycle through every blocked agent.
set -euo pipefail

agents=$(herdr agent list)
workspaces=$(herdr workspace list)

target=$(jq -nr --argjson a "$agents" --argjson w "$workspaces" '
  ($w.result.workspaces | map({key: .workspace_id, value: .number}) | from_entries) as $num
  | $a.result.agents
  | to_entries | map(.value + {i: .key})
  | sort_by($num[.workspace_id] // 1e9, .i)
  | (map(.focused) | index(true) // -1) as $cur
  | (.[$cur + 1:] + .[:$cur + 1]) as $ring
  | first(
      ($ring[] | select(.agent_status == "blocked")),
      ($ring[] | select(.agent_status == "done")),
      ($ring[] | select(.focused | not))
    )
  | .pane_id
')

[[ -n $target ]] && herdr agent focus "$target" >/dev/null
