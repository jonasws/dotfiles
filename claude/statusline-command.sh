#!/usr/bin/env bash
# Claude Code status line — Starship-style

input=$(cat)

# Colors (ANSI escape codes)
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Starship-inspired palette
BLUE='\033[38;5;33m'
CYAN='\033[38;5;39m'
GREEN='\033[38;5;76m'
YELLOW='\033[38;5;220m'
MAGENTA='\033[38;5;134m'
RED='\033[38;5;203m'
GRAY='\033[38;5;245m'

# Separator character used by Starship
SEP=" ${GRAY}|${RESET} "

# --- Directory ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -n "$cwd" ]; then
  # Shorten home dir to ~
  cwd="${cwd/#$HOME/~}"
  dir_part="${BOLD}${BLUE}${cwd}${RESET}"
else
  dir_part=""
fi

# --- Git branch ---
git_part=""
if [ -n "$cwd" ]; then
  expanded_cwd="${cwd/#\~/$HOME}"
  branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$expanded_cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_part="${GREEN} ${branch}${RESET}"
  fi
fi

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
if [ -n "$model" ]; then
  # Strip "Claude " prefix for brevity
  model_short="${model#Claude }"
  model_part="${MAGENTA}${model_short}${RESET}"
else
  model_part=""
fi

# --- Context usage ---
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
context_part=""
if [ -n "$remaining" ]; then
  remaining_int=$(printf '%.0f' "$remaining")
  if [ "$remaining_int" -le 10 ]; then
    ctx_color="$RED"
  elif [ "$remaining_int" -le 25 ]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$CYAN"
  fi
  context_part="${ctx_color}ctx:${remaining_int}%${RESET}"
fi

# --- Reasoning effort ---
effort_part=""
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  effort_part="${GRAY}effort:${effort}${RESET}"
fi

# --- Rate limits (Claude.ai subscription, optional) ---
rate_part=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five_pct" ]; then
  five_int=$(printf '%.0f' "$five_pct")
  if [ "$five_int" -ge 80 ]; then
    rate_color="$RED"
  elif [ "$five_int" -ge 50 ]; then
    rate_color="$YELLOW"
  else
    rate_color="$GRAY"
  fi
  rate_part="${rate_color}5h:${five_int}%${RESET}"
fi

# --- Caveman badge ---
caveman_part=""
caveman_flag="$HOME/.claude/.caveman-active"
if [ -f "$caveman_flag" ]; then
  caveman_mode=$(cat "$caveman_flag" 2>/dev/null)
  if [ "$caveman_mode" = "full" ] || [ -z "$caveman_mode" ]; then
    caveman_part="\033[38;5;172m[CAVEMAN]\033[0m"
  else
    caveman_suffix=$(echo "$caveman_mode" | tr '[:lower:]' '[:upper:]')
    caveman_part="\033[38;5;172m[CAVEMAN:${caveman_suffix}]\033[0m"
  fi
fi

# --- Assemble line ---
parts=()
[ -n "$caveman_part" ] && parts+=("$caveman_part")
[ -n "$dir_part" ] && parts+=("$dir_part")
[ -n "$git_part" ] && parts+=("$git_part")
[ -n "$model_part" ] && parts+=("$model_part")
[ -n "$effort_part" ] && parts+=("$effort_part")
[ -n "$context_part" ] && parts+=("$context_part")
[ -n "$rate_part" ] && parts+=("$rate_part")

line=""
for i in "${!parts[@]}"; do
  if [ "$i" -eq 0 ]; then
    line="${parts[$i]}"
  else
    line="${line}${SEP}${parts[$i]}"
  fi
done

printf "%b\n" "$line"
