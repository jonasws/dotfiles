#!/usr/bin/env bash
# Open a live markdown preview in a Herdr split pane.
#
# Usage: preview.sh [--direction right|down] [--focus] FILE
#        preview.sh --close FILE
#        preview.sh watch FILE        (internal: the loop that runs inside the pane)
#
# One pane per file. Running it again for a file whose pane is still open does
# nothing, because the pane already redraws on every save; --close removes it.
#
# The split targets the pane this runs in (--current), not whichever pane the
# UI has focused, so a second attached client cannot steer it somewhere else.
set -euo pipefail

self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/markdown-preview

die() { printf 'markdown-preview: %s\n' "$1" >&2; exit "${2:-1}"; }
abs() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$PWD" "$(basename "$1")"); }
state_file() { printf '%s/%s.pane' "$state_dir" "$(printf '%s' "$1" | shasum | cut -c1-16)"; }

# mdcat redraws on every change itself, including when an editor saves by
# replacing the file.
watch_loop() {
  exec mdcat --watch "$1"
}

direction=right focus=false close=false
while [[ ${1:-} == --* ]]; do
  case $1 in
    --direction) direction=${2:?--direction needs right or down}; shift 2 ;;
    --focus) focus=true; shift ;;
    --close) close=true; shift ;;
    *) die "unknown option $1" 2 ;;
  esac
done

if [[ ${1:-} == watch ]]; then
  shift
  watch_loop "${1:?usage: preview.sh watch FILE}"
fi

[[ $direction == right || $direction == down ]] || die "--direction must be right or down" 2
file=${1:?usage: preview.sh [--direction right|down] [--focus] FILE}
[[ -f $file ]] || die "no such file: $file"
file=$(abs "$file")
[[ $file != *\'* ]] || die "paths containing a single quote are not supported"

if [[ ${HERDR_ENV:-} != 1 ]] || ! command -v herdr >/dev/null; then
  printf 'markdown-preview: not inside Herdr. View it with: mdcat -p %q\n' "$file" >&2
  exit 3
fi
command -v mdcat >/dev/null || die "mdcat is not installed"
mdcat --help | grep -q -- --watch || die "this mdcat has no --watch; upgrade it"
command -v jq >/dev/null || die "jq is not installed"

sf=$(state_file "$file")

if $close; then
  if [[ -f $sf ]]; then
    herdr pane close "$(<"$sf")" >/dev/null 2>&1 || true
    rm -f "$sf"
    echo "closed preview of $file"
  else
    echo "no preview open for $file"
  fi
  exit 0
fi

if [[ -f $sf ]] && herdr pane get "$(<"$sf")" >/dev/null 2>&1; then
  echo "already open in pane $(<"$sf"); it refreshes when $file is saved"
  exit 0
fi

mkdir -p "$state_dir"
cmd="bash '$self' watch '$file'"
split=(pane split --current --direction "$direction" --cwd "$PWD")
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
printf '%s' "$pane" >"$sf"

if [[ ! -f $helper ]]; then
  sleep 1
  herdr pane run "$pane" "clear; $cmd; exit" >/dev/null
fi

echo "previewing $file in pane $pane (refreshes on save, Ctrl-C closes it)"
