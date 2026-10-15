#!/usr/bin/env bash
# Preview a Herdr pane for the `herdr-sessions` channel.
#
# An empty scope leaves only the channel's blank entry to preview, which is
# not a pane id, so anything not shaped like one (wAE:p8)
# prints a note instead of herdr's `pane_not_found`. Remaining arguments go to
# `herdr pane read`.
set -euo pipefail

pane_id="${1-}"
shift || true

if [[ ! "$pane_id" =~ ^[^[:space:]:]+:p[^[:space:]]+$ ]]; then
  echo "No panes in this scope"
  exit 0
fi

exec herdr pane read "$pane_id" "$@"
