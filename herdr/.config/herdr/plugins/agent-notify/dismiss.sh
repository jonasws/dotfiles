#!/usr/bin/env bash
# Clear a pane's outstanding notification once you actually reach that pane.
#
# Run by herdr's server for every pane.focused event, with the payload in
# HERDR_PLUGIN_EVENT_JSON. Reaching the pane answers the notification, whether
# you got there by clicking it, by prefix+a, or by clicking the sidebar -- so the
# toast should not still be sitting in Notification Center afterwards.
#
# Event-driven on purpose. herdr-focus-notify solves the same problem by spawning
# a background subshell per notification that polls pane visibility every two
# seconds for the notification's whole lifetime (up to an hour by default).
# pane.focused is in herdr's plugin hook event list, so the server can just tell
# us instead.
set -euo pipefail

PATH="/opt/homebrew/bin:${PATH:-/usr/bin:/bin}"

event="${HERDR_PLUGIN_EVENT_JSON:-}"
[[ -n "$event" ]] || exit 0

pane_id=$(jq -r '.pane_id // empty' <<<"$event")
[[ -n "$pane_id" ]] || exit 0

# Matches the --identifier notify.sh sends. Clearing an identifier with no
# delivered notification is a no-op, so this needs no "was there one" check.
grrr clear "herdr:$pane_id" >/dev/null 2>&1 || true
