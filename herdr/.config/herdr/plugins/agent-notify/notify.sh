#!/usr/bin/env bash
# Post a clickable macOS notification when an agent becomes blocked or done.
#
# Run by herdr's server for every pane.agent_status_changed event, with the
# plugin directory as the working directory and the event payload in
# HERDR_PLUGIN_EVENT_JSON.
set -euo pipefail

# The herdr server does not inherit an interactive shell's PATH, so grrr and jq
# have to be findable from a bare login environment. Prepend rather than replace:
# an earlier version clobbered PATH outright, which also hid herdr itself (a mise
# shim, not in any of these directories) and silently disabled the label lookup
# below. HERDR_BIN_PATH covers herdr in production; this covers the rest.
PATH="/opt/homebrew/bin:${PATH:-/usr/bin:/bin}"

# The app hosting herdr. Used only to decide whether you are already looking at
# the pane; focus.sh hardcodes the same identity for the click path.
TERMINAL_BUNDLE_ID="com.github.wez.wezterm"

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
herdr="${HERDR_BIN_PATH:-herdr}"

event="${HERDR_PLUGIN_EVENT_JSON:-}"
[[ -n "$event" ]] || exit 0

IFS=$'\t' read -r status pane_id workspace_id agent title < <(
  jq -r '[
    .agent_status,
    .pane_id,
    .workspace_id,
    (.display_agent // .agent // "agent"),
    (.title // "")
  ] | @tsv' <<<"$event"
)

# working and idle fire constantly and carry no decision for you. blocked means
# an agent is waiting on an answer; done means it finished and you have not
# looked yet. Those are the two worth interrupting for.
case "$status" in
blocked | done) ;;
*) exit 0 ;;
esac

# Two questions, not one: is this pane focused inside herdr, and is herdr's
# terminal the app you are actually looking at? Only both together mean you can
# see the change. An earlier version asked the first alone and stayed silent
# while you were in Slack with the pane merely focused behind it.
#
# Every unknown errs toward notifying. A missed notification is worse than a
# redundant one, and the osascript call in particular can fail for reasons that
# have nothing to do with where you are looking -- it needs Automation
# permission, which macOS prompts for on first use.
focused=''
label=''
snapshot=$("$herdr" api snapshot 2>/dev/null) || snapshot=''
if [[ -n "$snapshot" ]]; then
  focused=$(jq -r '.result.snapshot.focused_pane_id // empty' <<<"$snapshot")
  # Cosmetic: the event carries an opaque workspace_id ("w27"), the readable
  # label ("cnops-traincomposition") lives in the snapshot.
  label=$(
    jq -r --arg w "$workspace_id" \
      'first(.result.snapshot.workspaces[]? | select(.workspace_id == $w) | .label) // empty' \
      <<<"$snapshot"
  )
fi

if [[ -n "$focused" && "$pane_id" == "$focused" ]]; then
  frontmost=$(
    osascript -e 'tell application "System Events" to return bundle identifier of first application process whose frontmost is true' 2>/dev/null || true
  )
  if [[ "$frontmost" == "$TERMINAL_BUNDLE_ID" ]]; then
    exit 0
  fi
fi

workspace="${label:-$workspace_id}"

# The event's title is the pane's terminal title, which for Claude Code is the
# task topic -- true but not why the agent stopped. `agent explain` reports which
# detection rule matched and the screen region that triggered it, so a blocked
# notification can show the actual prompt you need to answer. Falls back to the
# title, then the pane id.
detail=$(
  "$herdr" agent explain "$pane_id" --json 2>/dev/null | jq -r '
    (.matched_rule.id) as $id
    | (first(.evaluated_rules[]? | select(.id == $id) | .evidence.region_preview) // "")
    | gsub("\\s+"; " ")
    | sub("^ +"; "")
    | sub(" +$"; "")
    | .[0:140]
  ' 2>/dev/null
) || detail=''

# blocked is a question waiting on you, so it gets a sound; done can wait for
# you to glance at the screen. Always a value, never an empty flag list -- this
# runs under macOS's bash 3.2 (env resolves the shebang before the PATH set
# above applies), where expanding an empty array trips `set -u`.
sound=none
if [[ "$status" == blocked ]]; then
  sound=Ping
fi

# growlrrr rather than terminal-notifier or alerter: both of those are built on
# NSUserNotification. growlrrr uses UNUserNotificationCenter, where --execute
# works and the app is configurable in System Settings like any other.
#
# --identifier reuses one slot per pane, so an agent churning through states
# updates its toast in place instead of leaving a pile. dismiss.sh clears that
# same identifier when you reach the pane. --threadId groups every herdr
# notification together in Notification Center.
#
# --execute is the whole point: the only click action that can carry the pane id.
# --reactivate is deliberately unused -- it special-cases iTerm2, Terminal.app,
# and Ghostty, and WezTerm is not among them. focus.sh does that job properly via
# `wezterm cli`.
grrr send \
  --title "$agent · $status" \
  --subtitle "$workspace" \
  --identifier "herdr:$pane_id" \
  --threadId herdr \
  --sound "$sound" \
  --execute "'$here/focus.sh' '$pane_id'" \
  "${detail:-${title:-$pane_id}}"
