#!/usr/bin/env bash
# File a tuios session under a space named after the work area its checkout
# sits in: ~/CX, ~/CNOPS, ~/CN-TERMINAL or ~/LIFLIG. A worktree lives under the
# same folder (../.worktrees/<repo>/<branch>), so its path maps the same way.
# ~/dotfiles and ~/dev/tuios go to "personal". Repos elsewhere stay in no space.
#
# It also sets the session's accent, which appearance.session_border carries on
# every pane border. Agents in the four work areas run inside nono
# (nono/launch-agent), so those sessions wear peach, the colour of the lock
# tuios-workspace-topic.py puts on their workspace label. Every other session wears a neutral grey; left
# without an accent, tuios would pick a hue of its own, and peach could be it.
#
#   session-space.sh SESSION PATH   file one session
#   session-space.sh --all          file every session by its checkout (backfill)
#   session-space.sh --window SESSION WINDOW
#                                   file SESSION unless it has a space, by its
#                                   checkout or else the window's folder
#
# Run by tuios-session.sh and by the after-new-worktree and after-new-window
# hooks (the latter catches sessions made by prefix+N or `tuios new`), which
# get the daemon's environment and `sh -c`, so tuios is looked up on PATH and then
# where it installs itself. Every failure exits 0: a missing space must not
# hold up a session.
set -u

tuios=$(command -v tuios) || tuios=$HOME/.local/share/tuios-nightly/bin/tuios
[[ -x $tuios ]] || exit 0

# macOS paths are case-insensitive and zoxide keeps whichever case was typed,
# so the first folder under $HOME compares case-folded (tr, not ${var,,}: the
# daemon may hand this script Apple's bash 3.2).
space_of() {
  local rel=${1#"$HOME"/}
  [[ $rel != "$1" ]] || return 0
  case $(printf %s "$rel" | tr A-Z a-z) in
    cx|cx/*) echo CX ;;
    cnops|cnops/*) echo CNOPS ;;
    cn-terminal|cn-terminal/*) echo CN-TERMINAL ;;
    liflig|liflig/*) echo LIFLIG ;;
    dotfiles|dotfiles/*|dev/tuios|dev/tuios/*) echo personal ;;
  esac
}

# Catppuccin Mocha peach and overlay0.
SANDBOX_ACCENT='#fab387'
PLAIN_ACCENT='#6c7086'

# SESSION SPACE: the space decides, since a session's folder in `tuios ls`
# follows its panes and can lie outside the checkout it was opened for.
accent_one() {
  local accent=$PLAIN_ACCENT
  case $2 in
    CX | CNOPS | CN-TERMINAL | LIFLIG) accent=$SANDBOX_ACCENT ;;
  esac
  "$tuios" set-session-accent -s "$1" "$accent" >/dev/null 2>&1 || true
}

file_one() {
  local space
  space=$(space_of "$2")
  accent_one "$1" "$space"
  [[ -n $space ]] || return 0
  "$tuios" set-session-space -s "$1" "$space" >/dev/null 2>&1 || true
}

if [[ ${1:-} == --window ]]; then
  [[ -n ${2:-} && -n ${3:-} ]] || exit 0
  # One daemon call for a session that is already filed, which is every window
  # after the first.
  info=$("$tuios" ls --json 2>/dev/null |
    jq -r --arg s "$2" '.[] | select(.name == $s) | [(.space // "-"), (.worktree.path // "-")] | @tsv' 2>/dev/null)
  IFS=$'\t' read -r space path <<<"$info"
  [[ $space == - ]] || exit 0
  [[ $path != - ]] ||
    path=$("$tuios" list-windows -s "$2" --json 2>/dev/null |
      jq -r --arg w "$3" '.windows[] | select(.window_id == $w) | .cwd // empty' 2>/dev/null)
  [[ -n $path ]] && file_one "$2" "$path"
elif [[ ${1:-} == --all ]]; then
  # Accents for every session, spaces only for those that have none yet.
  while IFS=$'\t' read -r name path space; do
    [[ -n $name && -n $path ]] || continue
    if [[ $space == - ]]; then file_one "$name" "$path"; else accent_one "$name" "$space"; fi
  done < <("$tuios" ls --json 2>/dev/null |
    jq -r '.[] | [.name, (.worktree.path // .dir // ""), (.space // "-")] | @tsv' 2>/dev/null)
else
  [[ -n ${1:-} && -n ${2:-} ]] && file_one "$1" "$2"
fi
exit 0
