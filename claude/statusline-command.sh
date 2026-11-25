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
  IFS= read -r worktree
  IFS= read -r transcript
} < <(jq -r '
  (.workspace.project_dir // .workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.effort.level // ""),
  (.context_window.remaining_percentage // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.prompt_cache.warm // ""),
  (.prompt_cache.expires_at // ""),
  (.workspace.git_worktree // .worktree.name // ""),
  (.transcript_path // "")
' <<<"$input")

# nono sets NONO_CAP_FILE in every sandboxed session. Claude Code's own Bash
# sandbox leaves no trace in the environment, so read sandbox.enabled from the
# settings files, the most specific one that sets it winning.
settings=()
for s in "$HOME/.claude/settings.json" "$cwd"/.claude/settings{,.local}.json; do
  [ -r "$s" ] && settings+=("$s")
done
if [ -n "${NONO_CAP_FILE:-}" ]; then
  sandbox=nono
elif [ "$(jq -sr 'map(.sandbox.enabled | select(. != null)) | last // false' \
  "${settings[@]}" 2>/dev/null)" = true ]; then
  sandbox=claude
else
  sandbox=
fi
case $sandbox in
  nono) sandbox_icon=🚧 ;;
  claude) sandbox_icon=🦺 ;;
esac

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
    [ -n "$sandbox" ] &&
      tuios set-agent-meta ${TUIOS_PANE_ID:+-w "$TUIOS_PANE_ID"} --source statusline \
        sandbox="$sandbox_icon"
  } </dev/null >/dev/null 2>&1 &
  disown
fi

cols=${COLUMNS:-120}
now=$(date +%s)

ESC=$'\033'
RESET="${ESC}[0m"
fg() { printf '%s[38;2;%d;%d;%dm' "$ESC" "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
GREEN=a6e3a1 RED=f38ba8 YELLOW=f9e2af
SAPPHIRE=74c7ec BLUE=89b4fa SURFACE1=45475a LAVENDER=b4befe
DIM=$(fg 7f849c)

# Row one is starship's own render of starship/claude.toml, so the directory and
# git tokens match the shell prompt. The model and the worktree arrive as
# env vars for the two segments that starship cannot compute itself.
git_extra=""
[ -n "$worktree" ] && git_extra+=$'\U000f0645'" $worktree"

model_text=""
if [ -n "$model" ]; then
  model_text=$'\U000f06a9'" ${model#Claude }"
  [ -n "$effort" ] && [ "$cols" -ge 90 ] && model_text+=" · $effort"
fi

row1=""
if [ -n "$cwd" ] && command -v starship >/dev/null; then
  row1=$(
    cd "$cwd" 2>/dev/null &&
      env GIT_OPTIONAL_LOCKS=0 STARSHIP_SHELL=sh \
        STARSHIP_CONFIG="${STARSHIP_CLAUDE_CONFIG:-$HOME/dotfiles/starship/claude.toml}" \
        CLAUDE_MODEL_TEXT="$model_text" ${git_extra:+"CLAUDE_GIT_EXTRA=$git_extra"} \
        starship prompt --path "$cwd" --terminal-width "$cols" 2>/dev/null | tr -d '\n'
  )
fi

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
    # Not a box-drawing dash: tuios reads a run of ━ or ─ as the prompt box's
    # border, takes the statusline row above it for the box, and holds its
    # message queue for a draft that is not there.
    bar+="▬"
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

# Artifacts published in this session, each title an OSC 8 link to its page.
# The transcript is the only record of them; a republish keeps the newest title.
if [ -r "$transcript" ]; then
  while IFS=$'\t' read -r title url; do
    parts+=("$(fg "$LAVENDER")"$'\U000f0339 \e]8;;'"$url"$'\e\\'"$title"$'\e]8;;\e\\'"$RESET")
  done < <(rg -F '"artifact_id"' "$transcript" 2>/dev/null |
    jq -rs '[.[] | .toolUseResult? | objects | select(.artifact_id and .url)]
      | group_by(.artifact_id) | map(last) | .[] | [.title, .url] | @tsv')
fi

row2=""
for p in "${parts[@]}"; do
  [ -n "$row2" ] && row2+="  ${DIM}│${RESET}  "
  row2+="$p"
done

# After the model: a construction sign inside nono, a safety vest in Claude
# Code's Bash sandbox, nothing when neither is on. Emoji, because a Nerd Font
# icon is squeezed into one cell and reads too small.
[ -n "$sandbox" ] && row1+=" ${sandbox_icon}"

printf '%s\n' "$row1"
[ -n "$row2" ] && printf ' %s\n' "$row2"
exit 0
