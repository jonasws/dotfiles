#!/usr/bin/env bash
# CN Kunde's Jira in a tuios popup (tv jira), typing the chosen issue's URL
# into the pane the key was pressed in, never submitted. A "shell" command key
# runs this; it opens the popup, waits for it and pastes what tv printed.
set -euo pipefail

pane=${TUIOS_ACTIVE_PANE_ID:-}
session=${TUIOS_SESSION:-}
cwd=${TUIOS_ACTIVE_PANE_CWD:-}
[[ -n $pane ]] || exit 0

# The same key closes the popup again.
tuios close-window ${session:+-s "$session"} jira >/dev/null 2>&1 && exit 0

pick() {
  local dir chosen params state text
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  chosen=$dir/chosen

  params=$(jq -n --arg s "$session" --arg pane "$pane" --arg cwd "${cwd:-$HOME}" --arg chosen "$chosen" '
    {name: "jira", width: "90%", height: "80%", wait: true,
     cwd_from: $pane, cwd: $cwd,
     command: ["bash", "-c", "exec tv jira >\"$1\"", "tv-jira", $chosen]}
    + (if $s != "" then {session: $s} else {} end)')
  tuios call --timeout 24h popup "$params" >/dev/null 2>&1 || true
  [[ -s $chosen ]] || return 0

  # A key runs outside every pane, so tuios would type into a pane that waits
  # on a prompt, where the text would answer it.
  state=$(tuios call get-agent-state \
    "$(jq -n --arg s "$session" --arg w "$pane" '{window: $w} + (if $s != "" then {session: $s} else {} end)')" |
    jq -r '.state // "none"') || return 0
  [[ $state != needs_input ]] || return 0

  text=$(tr -d '\r' <"$chosen" | tr '\n' ' ')
  [[ -n ${text// } ]] || return 0

  # paste: bracketed and with control characters removed, so the URL can
  # never press Enter in the pane.
  tuios call send-text "$(jq -n --arg s "$session" --arg w "$pane" --arg t "$text" '
    {window: $w, text: $t, paste: true} + (if $s != "" then {session: $s} else {} end)')" >/dev/null
}

pick </dev/null >/dev/null 2>&1 &
disown
