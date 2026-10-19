#!/usr/bin/env bash
# Open a live markdown preview with leaf in a Herdr split pane.
#
# Usage: preview.sh [--direction right|down] [--focus] FILE
#        preview.sh --close FILE
#
# One pane per file. Running it again for a file whose pane is still open does
# nothing, because leaf already reloads on every save; --close removes it.
#
# The split targets the pane this runs in (--current), not whichever pane the
# UI has focused, so a second attached client cannot steer it somewhere else.
set -euo pipefail

die() { printf 'markdown-preview: %s\n' "$1" >&2; exit "${2:-1}"; }
abs() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$PWD" "$(basename "$1")"); }

direction=right focus=false close=false
while [[ ${1:-} == --* ]]; do
  case $1 in
    --direction) direction=${2:?--direction needs right or down}; shift 2 ;;
    --focus) focus=true; shift ;;
    --close) close=true; shift ;;
    *) die "unknown option $1" 2 ;;
  esac
done

[[ $direction == right || $direction == down ]] || die "--direction must be right or down" 2
file=${1:?usage: preview.sh [--direction right|down] [--focus] FILE}
[[ -f $file ]] || die "no such file: $file"
file=$(abs "$file")
[[ $file != *\'* ]] || die "paths containing a single quote are not supported"

if [[ ${HERDR_ENV:-} != 1 ]] || ! command -v herdr >/dev/null; then
  printf 'markdown-preview: not inside Herdr. View it with: leaf -w %q\n' "$file" >&2
  exit 3
fi
command -v leaf >/dev/null || die "leaf is not installed (mise use -g github:RivoLink/leaf)"
command -v jq >/dev/null || die "jq is not installed"

# The pane is found again by its label and working directory rather than by an
# id stored on disk: the label names the file and the pane starts in the file's
# directory, so the pair is unique per absolute path. Nothing is written outside
# Herdr, which keeps the script usable from a sandbox that cannot write to
# ~/.local/state.
dir=$(dirname "$file")
label="leaf $(basename "$file")"
find_pane() {
  herdr pane list | jq -r --arg l "$label" --arg d "$dir" \
    '.result.panes[] | select(.label == $l and .cwd == $d) | .pane_id' | head -1
}

existing=$(find_pane)

if $close; then
  if [[ -n $existing ]]; then
    herdr pane close "$existing" >/dev/null 2>&1 || true
    echo "closed preview of $file"
  else
    echo "no preview open for $file"
  fi
  exit 0
fi

if [[ -n $existing ]]; then
  echo "already open in pane $existing; it reloads when $file is saved"
  exit 0
fi

# exec, so quitting leaf ends the pane's process and Herdr closes the pane.
cmd="exec leaf -w '$file'"
split=(pane split --current --direction "$direction" --cwd "$dir")
$focus || split+=(--no-focus)

# The user's fish setup can start a command in a fresh pane through the
# environment, which is the only race-free channel: keystrokes typed before the
# shell finishes starting are dropped. Without that helper, fall back to typing.
helper=$HOME/.config/fish/conf.d/50-herdr-exec.fish
if [[ -f $helper ]]; then
  split+=(--env "HERDR_EXEC_CMD=$cmd")
fi

pane=$(herdr "${split[@]}" | jq -r '.result.pane.pane_id')
[[ -n $pane && $pane != null ]] || die "herdr did not return a pane id"
herdr pane rename "$pane" "$label" >/dev/null

if [[ ! -f $helper ]]; then
  sleep 1
  herdr pane run "$pane" "$cmd" >/dev/null
fi

echo "previewing $file in pane $pane (reloads on save, q closes it)"
