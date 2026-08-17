#!/usr/bin/env bash
# Emit one absolute path per git repository on this machine.
#
# Two sources, in this order: zoxide's frecency list (most visited repos first),
# then a full `fd` scan of ~ for anything zoxide has never scored -- freshly
# cloned repos, mostly. Duplicates are dropped, keeping the zoxide position.
#
# The fd scan takes seconds on a large home directory, which is fine for a
# one-shot picker but not for `herdr-sessions`, whose source re-runs every two
# seconds while the picker is open. So the scan result is cached and refreshed
# in the background: every call returns immediately from zoxide plus whatever
# the cache holds, and a stale cache only means a newly cloned repo shows up a
# few seconds late.
set -euo pipefail

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/television"
cache="$cache_dir/git-repos"
lock="$cache.lock"
max_age_minutes=10
lock_age_minutes=5

mkdir -p "$cache_dir"

scan() {
  fd -g .git -HL -t d -d 3 --prune ~ -E 'Library' -E 'Application Support' --exec dirname '{}'
}

stale() {
  [[ ! -s $cache ]] && return 0
  [[ -n $(find "$cache" -mmin "+$max_age_minutes" -print -quit) ]]
}

# A crashed refresh would otherwise leave the lock behind and freeze the cache.
[[ -d $lock && -n $(find "$lock" -mmin "+$lock_age_minutes" -print -quit) ]] && rmdir "$lock" 2>/dev/null

# `mkdir` is the atomic test-and-set: the 2s refresh tick would otherwise start a
# new scan on top of the one still running. Output goes to /dev/null so the
# background job never holds this script's stdout open -- tv waits for EOF on the
# source pipe, and an inherited fd would stall the picker for the whole scan.
if stale && mkdir "$lock" 2>/dev/null; then
  (
    trap 'rmdir "$lock" 2>/dev/null' EXIT
    scan >"$cache.tmp" && mv "$cache.tmp" "$cache"
  ) >/dev/null 2>&1 &
fi

{
  zoxide query -l | while IFS= read -r dir; do
    [[ -d $dir/.git ]] && printf '%s\n' "$dir"
  done
  [[ -s $cache ]] && cat "$cache"
} | awk '!seen[$0]++'
