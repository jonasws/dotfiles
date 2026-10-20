#!/usr/bin/env bash
# Yazi for a Herdr popup, in the directory of the pane the key was pressed in.
# With `pick`, the files chosen with Enter are typed into that pane instead of
# opened: as @path for an agent, shell-quoted otherwise, and never submitted.
set -euo pipefail

cwd=${HERDR_ACTIVE_PANE_CWD:-$PWD}
cd "$cwd"

if [[ ${1:-} != pick ]]; then
  exec yazi
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
yazi --chooser-file="$dir/chosen"
[[ -s $dir/chosen && -n ${HERDR_ACTIVE_PANE_ID:-} ]] || exit 0

agent=$(herdr pane get "$HERDR_ACTIVE_PANE_ID" | jaq -r '.result.pane.agent // ""')

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

[[ -z $text ]] || herdr pane send-text "$HERDR_ACTIVE_PANE_ID" "$text"
