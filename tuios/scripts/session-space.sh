#!/usr/bin/env bash
# File a tuios session under a space named after the work area its checkout
# sits in: ~/CX, ~/CNOPS, ~/CN-TERMINAL or ~/LIFLIG. A worktree lives under the
# same folder (../.worktrees/<repo>/<branch>), so its path maps the same way.
# ~/dotfiles and ~/dev/tuios go to "personal". Repos elsewhere stay in no space.
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

file_one() {
  local space
  space=$(space_of "$2")
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
  while IFS=$'\t' read -r name path; do
    [[ -n $name && -n $path ]] && file_one "$name" "$path"
  done < <("$tuios" ls --json 2>/dev/null |
    jq -r '.[] | select(.space == null) | [.name, (.worktree.path // .dir // "")] | @tsv' 2>/dev/null)
else
  [[ -n ${1:-} && -n ${2:-} ]] && file_one "$1" "$2"
fi
exit 0
