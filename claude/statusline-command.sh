#!/usr/bin/env bash
# Claude Code status line: starship's powerline segments on the first row,
# context, rate limit and prompt cache on the second.
#
# Catppuccin Mocha, the palette of starship/starship.toml. Glyphs come from the
# Nerd Font Ghostty falls back to.

input=$(cat)

{
  IFS= read -r cwd
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r remaining
  IFS= read -r five_pct
  IFS= read -r five_reset
  IFS= read -r cache_warm
  IFS= read -r cache_expires
  IFS= read -r pr_number
  IFS= read -r pr_url
  IFS= read -r pr_state
  IFS= read -r worktree
  IFS= read -r repo_url
} < <(jq -r '
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.effort.level // ""),
  (.context_window.remaining_percentage // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.prompt_cache.warm // ""),
  (.prompt_cache.expires_at // ""),
  (.pr.number // ""),
  (.pr.url // ""),
  (.pr.review_state // ""),
  (.workspace.git_worktree // .worktree.name // ""),
  (if .workspace.repo.host and .workspace.repo.owner and .workspace.repo.name
   then "https://\(.workspace.repo.host)/\(.workspace.repo.owner)/\(.workspace.repo.name)"
   else "" end)
' <<<"$input")

# Feed tuios's rail and Inbox the model and the context left. tuios's own
# context key counts what is used, so the window is dropped from what
# agent-statusline sees and "context" is set here as the percent left. Cost is
# dropped too: a Max subscription does not pay per token. Called from here
# rather than with `tuios integration install --statusline`, which would
# rewrite settings.json. Detached, so the status line never waits on tuios.
if [ "${TUIOS_ENV:-}" = 1 ] && command -v tuios >/dev/null; then
  {
    jq -c 'del(.cost, .context_window)' <<<"$input" | tuios agent-statusline claude-code
    [ -n "$remaining" ] &&
      tuios set-agent-meta ${TUIOS_PANE_ID:+-w "$TUIOS_PANE_ID"} --source statusline \
        context="$(printf '%.0f' "$remaining")%"
  } </dev/null >/dev/null 2>&1 &
  disown
fi

cols=${COLUMNS:-120}
now=$(date +%s)

ESC=$'\033'
RESET="${ESC}[0m"
fg() { printf '%s[38;2;%d;%d;%dm' "$ESC" "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
bg() { printf '%s[48;2;%d;%d;%dm' "$ESC" "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
PEACH=fab387 GREEN=a6e3a1 MAUVE=cba6f7 RED=f38ba8 YELLOW=f9e2af
SAPPHIRE=74c7ec BLUE=89b4fa SURFACE1=45475a MANTLE=181825
DIM=$(fg 7f849c)
SEP_RIGHT=$''
CAP_LEFT=$''
CAP_RIGHT=$''

# shellcheck disable=SC1003 # the backslashes are the ST of OSC 8
link() { printf '%s]8;;%s%s\\%s%s]8;;%s\\' "$ESC" "$1" "$ESC" "$2" "$ESC" "$ESC"; }

# Powerline row: each segment is "colour|text"; arrows take the colour of the
# segment on each side, as starship's format does.
segments=()
add() { [ -n "$2" ] && segments+=("$1|$2"); }

if [ -n "$cwd" ]; then
  short="$cwd"
  # shellcheck disable=SC2088 # a literal ~ is the point
  case "$short" in
    "$HOME") short="~" ;;
    "$HOME"/*) short="~/${short#"$HOME"/}" ;;
  esac
  IFS=/ read -ra segs <<<"${short#/}"
  if [ "${#segs[@]}" -gt 3 ]; then
    printf -v short '%s/' "${segs[@]: -3}"
    short="…/${short%/}"
  fi
  add "$PEACH" "$short"
fi

if [ -n "$cwd" ]; then
  branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_text=$''" $branch"
    [ -n "$repo_url" ] && git_text=$(link "$repo_url/tree/$branch" "$git_text")
    [ -n "$worktree" ] && git_text+=" "$'\U000f0645'" $worktree"
    if [ -n "$pr_number" ]; then
      case "$pr_state" in
        approved) pr_mark="✓" ;;
        changes_requested) pr_mark="±" ;;
        draft) pr_mark="◌" ;;
        *) pr_mark="" ;;
      esac
      pr_text=$''" #$pr_number$pr_mark"
      [ -n "$pr_url" ] && pr_text=$(link "$pr_url" "$pr_text")
      git_text+="  $pr_text"
    fi
    add "$GREEN" "$git_text"
  fi
fi

if [ -n "$model" ]; then
  model_text=$'\U000f06a9'" ${model#Claude }"
  [ -n "$effort" ] && [ "$cols" -ge 90 ] && model_text+=" · $effort"
  add "$MAUVE" "$model_text"
fi

row1=""
prev=""
for seg in "${segments[@]}"; do
  colour=${seg%%|*}
  text=${seg#*|}
  if [ -z "$prev" ]; then
    row1+="$(fg "$colour")${CAP_LEFT}"
  else
    row1+="$(fg "$prev")$(bg "$colour")${SEP_RIGHT}"
  fi
  row1+="$(bg "$colour")$(fg "$MANTLE") ${text} "
  prev=$colour
done
[ -n "$prev" ] && row1+="${RESET}$(fg "$prev")${CAP_RIGHT}${RESET}"

# Second row: context left as a bar, then the 5-hour limit and the cache.
level_colour() { # value, warn at, alarm at, colour below warn
  if [ "$1" -ge "$3" ]; then echo "$RED"; elif [ "$1" -ge "$2" ]; then echo "$YELLOW"; else echo "$4"; fi
}

parts=()
if [ -n "$remaining" ]; then
  left=$(printf '%.0f' "$remaining")
  used=$((100 - left))
  colour=$(level_colour "$used" 75 90 "$SAPPHIRE")
  width=10
  filled=$(((left * width + 50) / 100))
  bar=""
  for ((i = 0; i < width; i++)); do
    if [ "$i" -eq "$filled" ]; then bar+="$(fg "$SURFACE1")"; fi
    bar+="━"
  done
  parts+=("$(fg "$colour")${bar}${RESET} ${DIM}ctx${RESET} $(fg "$colour")${left}%${RESET}")
fi

if [ -n "$five_pct" ]; then
  five=$(printf '%.0f' "$five_pct")
  five_left=$((100 - five))
  colour=$(level_colour "$five" 50 80 "$BLUE")
  reset_in=""
  if [ -n "$five_reset" ] && [ "$five_reset" -gt "$now" ]; then
    reset_in=" ${DIM}↻ $(date -r "$five_reset" +%H:%M)${RESET}"
  fi
  parts+=("$(fg "$colour")"$'\U000f051f'" 5h ${five_left}%${RESET}${reset_in}")
fi

if [ "$cache_warm" = "true" ] && [ "$cols" -ge 80 ]; then
  cache="$(fg "$GREEN")"$'\U000f0238'" cache"
  if [ -n "$cache_expires" ] && [ "$cache_expires" -gt "$now" ]; then
    cache+=" $(((cache_expires - now) / 60))m"
  fi
  parts+=("${cache}${RESET}")
elif [ "$cache_warm" = "false" ] && [ "$cols" -ge 80 ]; then
  parts+=("${DIM}"$'\U000f0717'" cache cold${RESET}")
fi

row2=""
for p in "${parts[@]}"; do
  [ -n "$row2" ] && row2+="  ${DIM}│${RESET}  "
  row2+="$p"
done

printf '%s\n' "$row1"
[ -n "$row2" ] && printf ' %s\n' "$row2"
exit 0
