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

# Everything below only applies when the picker was run from outside herdr.
[[ "${HERDR_ENV:-}" != 1 && -n "${WEZTERM_UNIX_SOCKET:-}" ]] || exit 0
command -v wezterm >/dev/null || exit 0

# `pane.focus` only moves focus *within* herdr. Run from outside a managed pane
# -- another WezTerm tab, say -- and the jump happens where you cannot see it,
# because nothing told the host terminal to switch. Bring it along, but only once
# the focus above has landed: switching first shows herdr still on the old pane
# and then moving, which reads as flicker.
#
# WEZTERM_UNIX_SOCKET is the gate: present means this shell was started by a live
# WezTerm GUI and the CLI can reach it. Do not read the pane id out of the herdr
# client's environment instead -- herdr's server outlives WezTerm, so panes it
# spawns inherit a dead GUI's WEZTERM_PANE and WEZTERM_UNIX_SOCKET. Asking the
# live GUI which pane currently runs herdr is the only answer that stays true.
#
# Best effort: a WezTerm that cannot be reached must not turn into a failed jump,
# since the focus above is the part that actually matters.
#
# --no-auto-start: without it the CLI tries to daemonize a mux-server whenever
# the socket is unreachable, stalling for seconds before failing anyway.
# `|| true` because an assignment from a failing substitution trips `set -e`.
host_pane=$(
  wezterm cli --no-auto-start list --format json 2>/dev/null |
    jq -r 'map(select(.title | test("herdr"; "i"))) | first | .pane_id // empty' || true
)

if [[ -n "$host_pane" ]]; then
  wezterm cli --no-auto-start activate-pane --pane-id "$host_pane" 2>/dev/null ||
    echo "herdr: could not switch the WezTerm tab" >&2
else
  echo "herdr: found no WezTerm pane running herdr" >&2
fi
