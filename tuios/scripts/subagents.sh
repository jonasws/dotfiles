#!/usr/bin/env bash
# Subagent viewers for the Claude pane a tuios key was pressed in, through
# claude/hooks/subagent-viewer.sh, which speaks herdr's API.
#
# Usage: subagents.sh toggle   viewer workspace: open, focus, or close it
#        subagents.sh stream   one tagged stream, for a popup
#
# A shell key runs with the tuios client's environment, not a pane's: no
# HERDR_SOCKET_PATH, and TUIOS_ACTIVE_PANE_ID is a tuios window id rather than
# the herdr id the hooks recorded. tuios's herdr socket takes a window id as a
# pane id, so one `pane get` translates it.
set -uo pipefail

mode=${1:-toggle}
die() { echo "subagents: $*" >&2; exit 1; }

# The client may have been started from a herdr pane, so a HERDR_SOCKET_PATH
# already set could name real herdr. tuios's own socket wins.
if [ -n "${TUIOS_SOCKET:-}" ]; then
  export HERDR_SOCKET_PATH="$TUIOS_SOCKET.herdr"
elif [ -z "${HERDR_SOCKET_PATH:-}" ]; then
  uid=$(id -u)
  for s in "${XDG_RUNTIME_DIR:-/nonexistent}/tuios/tuios.sock.herdr" \
    "/run/user/$uid/tuios/tuios.sock.herdr" "/tmp/tuios-$uid/tuios.sock.herdr"; do
    [ -S "$s" ] && { export HERDR_SOCKET_PATH=$s; break; }
  done
fi
[ -n "${HERDR_SOCKET_PATH:-}" ] || die "no tuios herdr socket found"
command -v "${HERDR_BIN_PATH:-herdr}" >/dev/null || die "herdr CLI not on PATH"

pane=${TUIOS_ACTIVE_PANE_ID:?no active pane}
info=$("${HERDR_BIN_PATH:-herdr}" pane get "$pane" 2>/dev/null)
HERDR_ACTIVE_PANE_ID=$(jq -r '.result.pane.pane_id // empty' <<<"$info")
HERDR_ACTIVE_TAB_ID=$(jq -r '.result.pane.tab_id // empty' <<<"$info")
[ -n "$HERDR_ACTIVE_PANE_ID" ] || die "pane $pane not found on $HERDR_SOCKET_PATH"
export HERDR_ACTIVE_PANE_ID HERDR_ACTIVE_TAB_ID

exec bash "$HOME/.claude/hooks/subagent-viewer.sh" "$mode"
