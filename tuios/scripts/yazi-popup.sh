#!/usr/bin/env bash
# Yazi in a tuios popup, in the folder of the pane the key was pressed in.
#
#   yazi-popup.sh        browse; runs inside the popup toggle-popup.sh opens
#   yazi-popup.sh pick   a "shell" command key: opens yazi in a popup, waits
#                        for it, and types the files chosen with Enter into
#                        the pane the key was pressed in: as @path for an
#                        agent, shell-quoted otherwise, and never submitted
set -euo pipefail

if [[ ${1:-} != pick ]]; then
  exec yazi
fi

pane=${TUIOS_ACTIVE_PANE_ID:-}
session=${TUIOS_SESSION:-}
cwd=${TUIOS_ACTIVE_PANE_CWD:-}
[[ -n $pane ]] || exit 0

# The same key closes the popup again.
tuios close-window ${session:+-s "$session"} yazi >/dev/null 2>&1 && exit 0

pick() {
  local dir chosen params state harness text path
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  chosen=$dir/chosen

  params=$(jq -n --arg s "$session" --arg pane "$pane" --arg cwd "${cwd:-$HOME}" --arg chosen "$chosen" '
    {name: "yazi", width: "80%", height: "60%", wait: true,
     cwd_from: $pane, cwd: $cwd, command: ["yazi", "--chooser-file=\($chosen)"]}
    + (if $s != "" then {session: $s} else {} end)')
  tuios call --timeout 24h popup "$params" >/dev/null 2>&1 || true
  [[ -s $chosen ]] || return 0

  # A key runs outside every pane, so tuios would type into a pane that waits
  # on a prompt, where the text would answer it.
  read -r state harness < <(tuios call get-agent-state \
    "$(jq -n --arg s "$session" --arg w "$pane" '{window: $w} + (if $s != "" then {session: $s} else {} end)')" |
    jq -r '"\(.state // "none") \(.harness_id // "")"') || return 0
  [[ $state != needs_input ]] || return 0

  text=
  while IFS= read -r path || [[ -n $path ]]; do
    [[ -n $path ]] || continue
    [[ -n $cwd ]] && path=${path#"$cwd"/}
    if [[ -n $harness ]]; then
      text+="@$path "
    else
      text+="$(printf '%q' "$path") "
    fi
  done <"$chosen"
  [[ -n $text ]] || return 0

  # paste: bracketed and with control characters removed, so a file name can
  # never press Enter in the pane.
  tuios call send-text "$(jq -n --arg s "$session" --arg w "$pane" --arg t "$text" '
    {window: $w, text: $t, paste: true} + (if $s != "" then {session: $s} else {} end)')" >/dev/null
}

pick </dev/null >/dev/null 2>&1 &
disown
