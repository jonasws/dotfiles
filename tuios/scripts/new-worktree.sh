#!/usr/bin/env bash
# The after-new-worktree hook: tuios has made a worktree session and waits for
# this before the first pane starts. Trust the worktree's mise config and
# install its tools, so the pane's shell and the agent find them.
#
# The daemon runs hooks with its own environment and `sh -c`, so mise is looked
# up on PATH and then where mise installs itself. Every failure exits 0: a
# missing tool must not hold up the session.
set -u

dir=${TUIOS_WORKTREE_PATH:-}
[[ -n $dir && -d $dir ]] || exit 0
cd "$dir" || exit 0

mise=$(command -v mise) || mise=$HOME/.local/bin/mise
[[ -x $mise ]] || exit 0

if compgen -G 'mise.toml' >/dev/null || compgen -G '.mise.toml' >/dev/null ||
  compgen -G 'mise/config.toml' >/dev/null || [[ -f .tool-versions ]]; then
  "$mise" trust --yes >/dev/null 2>&1 || true
  "$mise" install --yes >/dev/null 2>&1 || true
fi
exit 0
