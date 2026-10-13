#!/usr/bin/env bash
# Preview a Herdr pane for the `herdr-sessions` channel.
#
# A scope with no panes still triggers a preview with an empty id, which herdr
# answers with `pane_not_found`, so that case prints a note instead. Remaining
# arguments go to `herdr pane read`.
set -euo pipefail

pane_id="${1-}"
shift || true

if [[ -z "$pane_id" ]]; then
  echo "No panes in this scope"
  exit 0
fi

exec herdr pane read "$pane_id" "$@"
