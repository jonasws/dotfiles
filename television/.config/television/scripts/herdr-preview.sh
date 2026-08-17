#!/usr/bin/env bash
# Preview one entry of the `herdr-sessions` channel.
#
# The channel mixes two kinds of entry, so the preview has to branch on the key
# it is handed: a `~`-prefixed path is a repo (nothing running yet -- show what
# is in it), anything else is a pane id (show what the pane is doing).
#
# Usage: herdr-preview.sh <key> [visible|plain|history]
#
# The variant is what ctrl-f cycles through in the picker. Each kind of entry
# reads it its own way; `visible` is the default both fall back to.
set -euo pipefail

key="${1:?usage: herdr-preview.sh <key> [variant]}"
variant="${2:-visible}"

if [[ $key == '~'* || $key == /* ]]; then
  repo="${key/#\~/$HOME}"
  case "$variant" in
    plain) eza -la --git --color=always "$repo" ;;
    history) git -C "$repo" log -n 50 --stat --color=always ;;
    # `--color=always`: git is not writing to a tty here, so it drops colour
    # unless told otherwise.
    *) git -C "$repo" log -n 200 --pretty=medium --all --graph --color=always ;;
  esac
  exit 0
fi

# `visible` is the only source that works for both shells and agents painting on
# the alternate screen, hence the default. herdr only ever emits SGR sequences,
# which television parses into styled text via ansi_to_tui, so `--format ansi`
# renders the pane in its real colours; the plain-text variant is the fallback
# for when that renders badly.
case "$variant" in
  history) herdr pane read "$key" --source recent-unwrapped --lines 400 --format ansi ;;
  plain) herdr pane read "$key" --source visible --lines 200 ;;
  *) herdr pane read "$key" --source visible --lines 200 --format ansi ;;
esac
