#!/usr/bin/env bash
# Focus a Herdr pane by id.
#
# No CLI command can do this: `herdr pane focus` is directional, `herdr agent
# focus` rejects panes that do not host a recognised agent, and `herdr tab
# focus` only reaches a tab's *active* pane. The socket API's `pane.focus` is a
# layout operation, so it targets any pane exactly regardless of whether it runs
# a shell, an agent, or an arbitrary long-running command.
#
# Exits 0 on success, 1 on any transport or API error.
set -euo pipefail

pane_id="${1:?usage: herdr-focus.sh <pane_id>}"
socket="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"

# Newline-delimited JSON over a unix socket. The server answers one request per
# connection and then closes, so a plain write-then-read is all that is needed
# and nc's -q/-w timeout differences never come into play.
response=$(
  jq -nc --arg pane "$pane_id" \
    '{id: "tv-herdr-focus", method: "pane.focus", params: {pane_id: $pane}}' |
    nc -U "$socket"
)

if [[ -z "$response" ]]; then
  echo "herdr: no response from $socket" >&2
  exit 1
fi

if jq -e 'has("error")' >/dev/null <<<"$response"; then
  jq -r '.error | "herdr: pane.focus failed: \(.code): \(.message)"' >&2 <<<"$response"
  exit 1
fi
