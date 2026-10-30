#!/usr/bin/env bash
# Yazi for a tuios popup, in the directory of the pane the key was pressed in.
# With `pick`, the files chosen with Enter are typed into that pane instead of
# opened: as @path for an agent, shell-quoted otherwise, and never submitted.
set -euo pipefail

cwd=${TUIOS_ACTIVE_PANE_CWD:-$PWD}
cd "$cwd"

if [[ ${1:-} != pick ]]; then
  exec yazi
fi

pane=${TUIOS_ACTIVE_PANE_ID:-}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
yazi --chooser-file="$dir/chosen"
[[ -s $dir/chosen && -n $pane ]] || exit 0

agent=$(tuios list-windows --json |
  jq -r --arg w "$pane" 'first(.windows[] | select(.window_id == $w) | .agent_state // "" | select(. != "none")) // ""')

text=
while IFS= read -r path || [[ -n $path ]]; do
  [[ -n $path ]] || continue
  path=${path#"$cwd"/}
  if [[ -n $agent ]]; then
    text+="@$path "
  else
    text+="$(printf '%q' "$path") "
  fi
done <"$dir/chosen"

[[ -z $text ]] || tuios send-text -w "$pane" "$text"
