#!/usr/bin/env bash
# Open a repository as a tuios session named after its directory, or switch to
# the session already open there.
#
# The name, not the label, is what `-s`, `tuios attach` and the `session:`
# selector take, so other agents can reach the repo's session as `-s <repo>`.
# A session counts as the repo's when its checkout is the repo (`tuios ls`
# reports it per session), else when it carries the repo's name. One that tuios
# named `session-<hex>` gets the repo's name on the way.
#
# macOS paths are case-insensitive and zoxide keeps whichever case was typed
# (~/cx and ~/CX), so paths compare case-folded.
set -euo pipefail

repo_path="${1:?usage: tuios-session.sh <repo_path>}"
repo_path="${repo_path%/}"
name="${repo_path##*/}"

sessions=$(tuios ls --json)

session=$(
  jq -r --arg path "$repo_path" --arg name "$name" '
    ($path | ascii_downcase) as $p
    | (map(select((.worktree.path // "" | ascii_downcase) == $p)) | first | .name)
      // (map(select(.name == $name and .worktree == null)) | first | .name)
      // empty
  ' <<<"$sessions"
)

# Another repo with the same directory name holds the name already.
if [[ -z $session ]] && jq -e --arg name "$name" 'any(.[]; .name == $name)' <<<"$sessions" >/dev/null; then
  parent="${repo_path%/*}"
  name="${parent##*/}-$name"
fi

if [[ $session == session-* ]] && ! jq -e --arg name "$name" 'any(.[]; .name == $name)' <<<"$sessions" >/dev/null; then
  tuios rename-session "$session" "$name" >/dev/null
  session=$name
fi

tuios switch-session --create --cwd "$repo_path" "${session:-$name}" >/dev/null
