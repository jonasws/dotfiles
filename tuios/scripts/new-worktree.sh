#!/usr/bin/env bash
# The after-new-worktree hook: tuios has made a worktree session and waits for
# this before the first pane starts. Trust the worktree's mise config and
# install its tools, so the pane's shell and the agent find them.
#
# Trust carries over from the main checkout only: a worktree of a repo whose
# own config I have not trusted stays untrusted, so a branch cannot bring in
# config that runs without my say.
#
# The daemon runs hooks with its own environment and `sh -c`, so mise is looked
# up on PATH and then where mise installs itself. Every failure exits 0: a
# missing tool must not hold up the session.
set -u

dir=${TUIOS_WORKTREE_PATH:-}
root=${TUIOS_WORKTREE_REPO_ROOT:-}
[[ -n $dir && -d $dir && -n $root && -d $root ]] || exit 0

mise=$(command -v mise) || mise=$HOME/.local/bin/mise
[[ -x $mise ]] || exit 0

# `mise trust --show`, run in a folder, prints "PATH: trusted" or
# "PATH: untrusted" for that folder and for each ancestor with mise config (`~`
# among them), with $HOME written as ~. Only the folder's own line counts; it
# has none when the folder has no config of its own.
trust_of() {
  local real
  real=$(cd "$1" && pwd -P) || return 0
  (cd "$1" && "$mise" trust --show 2>/dev/null) |
    awk -v want="${real/#$HOME/\~}" -F': ' '$1 == want { print $2; exit }'
}

cd "$dir" || exit 0
case $(trust_of "$dir") in
  trusted) ;;
  untrusted)
    [[ $(trust_of "$root") == trusted ]] || exit 0
    "$mise" trust --yes >/dev/null 2>&1 || exit 0
    ;;
  *) exit 0 ;;
esac
"$mise" install --yes >/dev/null 2>&1 || true
exit 0
