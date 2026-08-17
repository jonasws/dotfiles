#!/usr/bin/env bash
# Jump to one entry of the `herdr-sessions` channel.
#
# Same branch as the preview: a `~`-prefixed path is a repo with nothing running
# on it, so it needs a workspace opened (or focused, if one turns out to exist
# after all); anything else is a pane id and just needs focusing.
#
# Exits 0 on success, 1 on any transport or API error.
set -euo pipefail

key="${1:?usage: herdr-jump.sh <pane_id|repo_path>}"
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $key == '~'* || $key == /* ]]; then
  exec "$scripts/herdr-workspace.sh" "${key/#\~/$HOME}"
fi

exec "$scripts/herdr-focus.sh" "$key"
