#!/usr/bin/env bash
# A television channel in a tuios popup, typing what was chosen into the pane
# the key was pressed in, never submitted. A "shell" command key runs this: it
# opens the popup, waits for it and pastes what tv printed.
#
# Usage: tv-popup.sh NAME CHANNEL paths|text [WIDTH HEIGHT]
#
#   paths  one entry per line is a file: as @path for an agent, shell-quoted
#          otherwise
#   text   the lines are joined with spaces, as they are
#
# The popup opens in the folder of that pane. NAME is the popup's name, so the
# same key closes it again.
set -euo pipefail

name=${1:?usage: tv-popup.sh NAME CHANNEL paths|text [WIDTH HEIGHT]}
channel=${2:?}
mode=${3:?}
width=${4:-90%} height=${5:-80%}

pane=${TUIOS_ACTIVE_PANE_ID:-}
session=${TUIOS_SESSION:-}
cwd=${TUIOS_ACTIVE_PANE_CWD:-}
[[ -n $pane ]] || exit 0

tuios close-window ${session:+-s "$session"} "$name" >/dev/null 2>&1 && exit 0

pick() {
  local dir chosen params state harness text path
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  chosen=$dir/chosen

  params=$(jq -n --arg s "$session" --arg pane "$pane" --arg cwd "${cwd:-$HOME}" \
    --arg name "$name" --arg channel "$channel" --arg chosen "$chosen" \
    --arg width "$width" --arg height "$height" '
    {name: $name, width: $width, height: $height, wait: true,
     cwd_from: $pane, cwd: $cwd,
     command: ["bash", "-c", "exec tv \"$1\" >\"$2\"", "tv-popup", $channel, $chosen]}
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
  if [[ $mode == paths ]]; then
    while IFS= read -r path || [[ -n $path ]]; do
      [[ -n $path ]] || continue
      [[ -n $cwd ]] && path=${path#"$cwd"/}
      if [[ -n $harness ]]; then
        text+="@$path "
      else
        text+="$(printf '%q' "$path") "
      fi
    done <"$chosen"
  else
    text=$(tr -d '\r' <"$chosen" | tr '\n' ' ')
  fi
  [[ -n ${text// } ]] || return 0

  # paste: bracketed and with control characters removed, so a file name can
  # never press Enter in the pane.
  tuios call send-text "$(jq -n --arg s "$session" --arg w "$pane" --arg t "$text" '
    {window: $w, text: $t, paste: true} + (if $s != "" then {session: $s} else {} end)')" >/dev/null
}

pick </dev/null >/dev/null 2>&1 &
disown
