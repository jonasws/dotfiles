#!/usr/bin/env bash
# Emit one absolute path per git repository on this machine.
#
# Two sources, in this order: zoxide's frecency list (most visited repos first),
# then an `fd` scan of ~ for anything zoxide has never scored -- freshly cloned
# repos, mostly. Duplicates are dropped, keeping the zoxide position.
#
# --format '{//}' prints each .git's parent directory without a process per
# match; `--exec dirname` made the scan about 6x slower, which is what once
# justified caching it.
set -euo pipefail

{
  # `if`, not `&&`: the loop's status is its last test, and a trailing non-repo
  # would otherwise abort the group under `set -e`.
  # realpath restores the on-disk casing: zoxide keeps whatever case a path was
  # typed in (~/cnops), and on a case-insensitive volume that would slip past
  # the dedupe next to fd's ~/CNOPS.
  zoxide query -l | while IFS= read -r dir; do
    if [[ -d $dir/.git ]]; then printf '%s\0' "$dir"; fi
  done | xargs -0 realpath
  fd -g .git -HL -t d -d 3 --prune ~ -E 'Library' -E 'Application Support' --format '{//}'
} | awk '!seen[$0]++'
