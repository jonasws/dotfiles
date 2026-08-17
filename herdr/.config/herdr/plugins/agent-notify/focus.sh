#!/usr/bin/env bash
# Notification click handler: focus a herdr pane and bring WezTerm to it.
#
# Invoked by growlrrr's --execute, so it runs from the notification daemon rather
# than from a shell: no interactive PATH, and no guarantee about which
# environment it inherits.
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

pane_id="${1:?usage: focus.sh <pane_id>}"

# The herdr half. HERDR_ENV and the WEZTERM_* pair are scrubbed because this
# process may inherit them from the herdr *server*, where both are wrong:
# HERDR_ENV=1 is injected into every plugin command, and the server outlives
# WezTerm, so its WEZTERM_UNIX_SOCKET can point at a GUI that is long gone.
# Clearing them makes herdr-focus.sh stop after its pane.focus request -- its own
# WezTerm branch is gated on exactly those variables -- and the WezTerm half is
# done below instead, against the live GUI.
#
# HERDR_SOCKET_PATH is deliberately left alone; herdr-focus.sh falls back to the
# default session socket when it is absent, which is correct here either way.
env -u HERDR_ENV -u WEZTERM_UNIX_SOCKET -u WEZTERM_PANE \
  "$HOME/.config/television/scripts/herdr-focus.sh" "$pane_id"

# The WezTerm half, ordered after the focus above for the same reason
# herdr-focus.sh orders it that way: switching first shows herdr still on the old
# pane and then moving, which reads as flicker.
#
# Ask the live GUI which pane runs herdr rather than trusting an inherited pane
# id. --no-auto-start keeps the CLI from daemonizing a mux-server for seconds
# before failing anyway. Best effort throughout: an unreachable WezTerm must not
# turn a successful pane focus into a failed click.
host_pane=$(
  wezterm cli --no-auto-start list --format json 2>/dev/null |
    jq -r 'map(select(.title | test("herdr"; "i"))) | first | .pane_id // empty' || true
)

if [[ -n "$host_pane" ]]; then
  wezterm cli --no-auto-start activate-pane --pane-id "$host_pane" 2>/dev/null || true
fi

# activate-pane switches the tab inside WezTerm but does not raise the app, and
# a notification is always clicked from somewhere else.
open -b com.github.wez.wezterm
