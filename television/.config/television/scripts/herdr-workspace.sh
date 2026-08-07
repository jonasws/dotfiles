#!/usr/bin/env bash
# Open a repository as a Herdr workspace, or focus it if one is already open.
#
# Herdr's socket API exposes no "workspace by cwd" lookup, so this scans
# `pane list` (every pane in every workspace, since panes -- not
# workspaces -- carry a `cwd`) for one whose cwd matches the selected repo.
# A match means the repo already has a workspace open: focus it instead of
# spawning a duplicate.
#
# Exits 0 on success, 1 on any transport or API error.
set -euo pipefail

repo_path="${1:?usage: herdr-workspace.sh <repo_path>}"

existing_workspace=$(
  herdr pane list |
    jq -r --arg path "$repo_path" \
      '.result.panes[] | select(.cwd == $path or .foreground_cwd == $path) | .workspace_id' |
    head -n1
)

if [[ -n "$existing_workspace" ]]; then
  herdr workspace focus "$existing_workspace" >/dev/null
else
  label="${repo_path##*/}"
  herdr workspace create --cwd "$repo_path" --label "$label" --focus >/dev/null
fi

# Everything below only applies when the picker was run from outside herdr.
[[ "${HERDR_ENV:-}" != 1 && -n "${WEZTERM_UNIX_SOCKET:-}" ]] || exit 0
command -v wezterm >/dev/null || exit 0

# Workspace focus/create only moves focus *within* herdr. Run from outside a
# managed pane -- another WezTerm tab, say -- and the jump happens where you
# cannot see it, because nothing told the host terminal to switch. Bring it
# along, but only once the focus above has landed: switching first shows
# herdr still on the old workspace and then moving, which reads as flicker.
#
# Best effort: a WezTerm that cannot be reached must not turn into a failed
# jump, since the focus above is the part that actually matters.
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
