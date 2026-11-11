#!/usr/bin/env bash
# git-worktrees for the repository of the pane prefix+R was pressed in, in the
# popup toggle-popup.sh opens in that pane's folder.
set -euo pipefail

dir=$PWD
if ! common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  gum log --level warn "Not in a git repository: ${dir/#$HOME/\~}"
  sleep 1.5
  exit 0
fi
repo=${common%/.git}
export TV_WORKTREE_REPO=$repo
exec ~/.config/tuios/scripts/close-on-leave.sh tv git-worktrees --input-header "worktrees · ${repo##*/}"
