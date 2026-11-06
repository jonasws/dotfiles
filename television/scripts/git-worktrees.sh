#!/usr/bin/env bash
# The git-worktrees television channel: the checkouts of one repository, the
# main one first. In tuios each row also shows the session open in it.
#
# Usage: git-worktrees.sh count|list|path|preview|open|rm [TOKEN]
#
# The repository is $TV_WORKTREE_REPO, which git-repos sets for its Ctrl-W,
# else the one the current directory is in. Either way the list starts from
# the main checkout, so it is the same from inside a linked worktree. A row
# begins with its token, the branch (or @<sha> for a detached HEAD), which git
# keeps free of spaces, so the channel reads it back with
# {strip_ansi|split: :0}. Worktrees git marks prunable, whose folder is gone,
# are left out.
#
# macOS paths are case-insensitive and zoxide keeps whichever case was typed,
# so paths compare case-folded, as in tuios-session.sh.
set -euo pipefail

scripts="$(dirname "$(realpath "$0")")"
common=$(git -C "${TV_WORKTREE_REPO:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
  echo "Not in a git repository: ${TV_WORKTREE_REPO:-$PWD}" >&2
  exit 1
}
repo=${common%/.git}
export TV_WORKTREE_REPO=$repo

in_tuios() { [[ ${TUIOS_ENV:-} == 1 ]]; }
show_picker() { exec tv git-worktrees --input-header "worktrees · ${repo##*/}"; }

# path<TAB>token, one line per live checkout, the main one first.
checkouts() {
  git -C "$repo" worktree list --porcelain | awk '
    function emit() { if (path != "" && !prunable) printf "%s\t%s\n", path, token }
    /^worktree / { emit(); path = substr($0, 10); token = ""; prunable = 0 }
    /^HEAD /     { if (token == "") token = "@" substr($2, 1, 7) }
    /^branch /   { token = substr($2, 12) }
    /^prunable/  { prunable = 1 }
    END          { emit() }'
}

path_of() {
  checkouts | awk -F'\t' -v t="$1" '$2 == t { print $1; exit }'
}

# The tuios worktree row for a path, as JSON, or nothing.
session_row() {
  in_tuios || return 0
  tuios worktree ls --json |
    jq -c --arg p "$1" 'map(select((.path | ascii_downcase) == ($p | ascii_downcase))) | first // empty'
}

paint() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

list() {
  local sessions rows=() path token row session state changes ahead merged glyph color width=0
  sessions='[]'
  in_tuios && sessions=$(tuios worktree ls --json)
  while IFS=$'\t' read -r path token; do
    (( ${#token} > width )) && width=${#token}
    rows+=("$path"$'\t'"$token")
  done < <(checkouts)

  for entry in "${rows[@]}"; do
    path=${entry%%$'\t'*}
    token=${entry#*$'\t'}
    row=$(jq -c --arg p "$path" \
      'map(select((.path | ascii_downcase) == ($p | ascii_downcase))) | first // empty' <<<"$sessions")
    session='' state='' ahead='' merged=false
    if [[ -n $row ]]; then
      # A tab is IFS whitespace, so an empty field would shift the rest left.
      IFS=$'\x1f' read -r session state changes ahead merged < <(
        jq -r '[.session, (.state // ""), (.changes // 0), (.ahead // ""), (.merged // false)]
          | map(tostring) | join("\u001f")' <<<"$row")
    else
      changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    fi

    case $state in
      errored) glyph='×' color='1;91' ;;
      needs_input) glyph='◉' color='1;91' ;;
      working) glyph='◐' color='33' ;;
      done | idle) glyph='√' color='92' ;;
      '') glyph='·' color='37' ;;
      *) glyph='●' color='96' ;;
    esac

    printf '%s' "$(paint 1 "$(printf "%-${width}s" "$token")")"
    if in_tuios; then
      printf '  %s %s' "$(paint "$color" "$glyph")" \
        "$(paint "$color" "$(printf '%-12s' "${state:-no session}")")"
    fi
    [[ -n $session ]] && printf '  %s' "$(paint 94 "$session")"
    [[ $path == "$repo" ]] && printf '  %s' "$(paint 35 main)"
    (( changes > 0 )) && printf '  %s' "$(paint 33 "~$changes")"
    [[ -n $ahead && $ahead != 0 ]] && printf '  %s' "$(paint 36 "+$ahead")"
    [[ $merged == true && $path != "$repo" ]] && printf '  %s' "$(paint 32 merged)"
    printf '  %s\n' "$(paint 90 "${path/#$HOME/\~}")"
  done
}

preview() {
  local path row
  path=$(path_of "$1")
  [[ -n $path ]] || { echo "No checkout for $1"; return; }
  row=$(session_row "$path")
  printf '%s\n' "$(paint 90 "${path/#$HOME/\~}")"
  if [[ -n $row ]]; then
    jq -r '"session \(.session)  \(.state // "")  \(.windows // 0) windows"' <<<"$row"
  fi
  echo
  git -C "$path" -c color.status=always status --short
  echo
  git -C "$path" log -n 40 --graph --oneline --decorate --color
}

# Lands on the checkout with a pane focused: its tuios session or Herdr
# workspace, created when there is none, or a shell there outside both.
open() {
  local path session
  path=$(path_of "$1")
  [[ -n $path ]] || { echo "No checkout for $1" >&2; exit 1; }
  if [[ -n ${REX_SESSION:-} ]]; then
    exec "$scripts/rex-session.sh" "$path"
  elif in_tuios; then
    "$scripts/tuios-session.sh" "$path"
    # A session whose last pane closed stays open with nothing to focus.
    session=$(tuios ls --json | jq -r --arg p "$path" '
      map(select((.worktree.path // "" | ascii_downcase) == ($p | ascii_downcase))) | first // empty
      | select((.windows // []) | length == 0) | .name')
    [[ -z $session ]] || tuios new-window -s "$session" --cwd "$path" >/dev/null
  elif [[ ${HERDR_ENV:-} == 1 ]]; then
    exec "$scripts/herdr-workspace.sh" "$path"
  else
    cd "$path" && exec "${SHELL:-/bin/sh}"
  fi
}

# Removes the checkout and its session, never the branch. A dirty checkout is
# refused first, and only an explicit choice stashes or discards its changes.
rm_checkout() {
  local path session err choice
  path=$(path_of "$1")
  [[ -n $path ]] || { echo "No checkout for $1" >&2; exit 1; }
  if [[ $path == "$repo" ]]; then
    gum log --level warn "The main checkout stays."
    sleep 1
    show_picker
  fi

  session=$(session_row "$path" | jq -r '.session // empty')
  if [[ -n $session ]]; then
    if ! err=$(tuios worktree rm "$session" 2>&1); then
      printf '%s\n' "$err"
      choice=$(gum choose --header "Remove $1 anyway?" Cancel "Stash changes" "Discard changes") || choice=Cancel
      case $choice in
        "Stash changes") tuios worktree rm "$session" --stash ;;
        "Discard changes") tuios worktree rm "$session" --force ;;
      esac
    fi
  elif ! err=$(git -C "$repo" worktree remove "$path" 2>&1); then
    printf '%s\n' "$err"
    if gum confirm --default=false "Discard the changes in $1 and remove it?"; then
      git -C "$repo" worktree remove --force "$path"
    fi
  fi
  show_picker
}

case ${1:-} in
  count) checkouts | wc -l | tr -d ' ' ;;
  list) list ;;
  path) path_of "${2:?token}" ;;
  preview) preview "${2:?token}" ;;
  open) open "${2:?token}" ;;
  rm) rm_checkout "${2:?token}" ;;
  *) echo "usage: git-worktrees.sh count|list|path|preview|open|rm [TOKEN]" >&2; exit 2 ;;
esac
