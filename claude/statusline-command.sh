#!/usr/bin/env bash
# Claude Code status line — Starship-style

input=$(cat)

# One jq pass; each field on its own line so empty values keep their slot.
{
  IFS= read -r cwd
  IFS= read -r model
  IFS= read -r remaining
  IFS= read -r effort
  IFS= read -r five_pct
  IFS= read -r session_id
} < <(jq -r '
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.context_window.remaining_percentage // ""),
  (.effort.level // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.session_id // "")
' <<<"$input")

# Catppuccin Mocha, matching starship/starship.toml and herdr's theme.
rgb() { printf '\033[38;2;%d;%d;%dm' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
RESET='\033[0m'
BOLD='\033[1m'
PEACH=$(rgb fab387)
GREEN=$(rgb a6e3a1)
MAUVE=$(rgb cba6f7)
SAPPHIRE=$(rgb 74c7ec)
YELLOW=$(rgb f9e2af)
RED=$(rgb f38ba8)
OVERLAY=$(rgb 7f849c)

SEP=" ${OVERLAY}|${RESET} "

# --- Directory ---
# Same truncation as starship's [directory]: last 3 segments, "…/" prefix.
dir_part=""
if [ -n "$cwd" ]; then
  short="$cwd"
  case "$short" in
    "$HOME") short="~" ;;
    "$HOME"/*) short="~/${short#"$HOME"/}" ;;
  esac
  IFS=/ read -ra segs <<<"${short#/}"
  if [ "${#segs[@]}" -gt 3 ]; then
    printf -v short '%s/' "${segs[@]: -3}"
    short="…/${short%/}"
  fi
  dir_part="${BOLD}${PEACH}${short}${RESET}"
fi

# --- Git branch ---
git_part=""
if [ -n "$cwd" ]; then
  branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$branch" ] && git_part="${GREEN} ${branch}${RESET}"
fi

# --- Model ---
model_part=""
[ -n "$model" ] && model_part="${MAUVE}${model#Claude }${RESET}"

# --- Context usage ---
context_part=""
if [ -n "$remaining" ]; then
  remaining_int=$(printf '%.0f' "$remaining")
  if [ "$remaining_int" -le 10 ]; then
    ctx_color="$RED"
  elif [ "$remaining_int" -le 25 ]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$SAPPHIRE"
  fi
  context_part="${ctx_color}ctx:${remaining_int}%${RESET}"
fi

# --- Reasoning effort ---
effort_part=""
[ -n "$effort" ] && effort_part="${OVERLAY}effort:${effort}${RESET}"

# --- Rate limits (Claude.ai subscription, optional) ---
rate_part=""
if [ -n "$five_pct" ]; then
  five_int=$(printf '%.0f' "$five_pct")
  if [ "$five_int" -ge 80 ]; then
    rate_color="$RED"
  elif [ "$five_int" -ge 50 ]; then
    rate_color="$YELLOW"
  else
    rate_color="$OVERLAY"
  fi
  rate_part="${rate_color}5h:${five_int}%${RESET}"
fi

# --- Assemble line ---
parts=()
for p in "$dir_part" "$git_part" "$model_part" "$effort_part" "$context_part" "$rate_part"; do
  [ -n "$p" ] && parts+=("$p")
done

line=""
for i in "${!parts[@]}"; do
  if [ "$i" -eq 0 ]; then
    line="${parts[$i]}"
  else
    line="${line}${SEP}${parts[$i]}"
  fi
done

# --- herdr sidebar tokens ---
# Mirrors this agent into its row in herdr's sidebar (rows_by_agent.claude in
# herdr/config.toml):
#   $ctx                  context remaining, a bare number because herdr's
#                         gt/lt colour rules only match values that parse as one
#   $tasks                done/total in this session's TASKS-<session-id>.md
#   $task                 its first unchecked item, the one being worked on
#   $title_l1, $title_l2  the session topic word-wrapped over two rows, since
#                         herdr truncates a row instead of wrapping it
# No --seq: herdr keeps a source's highest seq for the pane's lifetime, so one
# bad value would silence every later report. Backgrounded with every fd closed
# so the status line never waits on herdr.

# Columns a title row gets with herdr's default 26-column sidebar: the first
# row loses one column plus the state icon, later rows lose three. herdr's API
# cannot read the real width, so this assumes the divider was not dragged.
TITLE_WIDTH=23

# wrap_title <text> <first-row width>: sets title_l1 and title_l2
wrap_title() {
  local words word w1=$2 need
  title_l1="" title_l2=""
  read -ra words <<<"$1"
  for word in "${words[@]}"; do
    need=$((${#title_l1} + ${#word} + (${#title_l1} > 0)))
    if [ -z "$title_l2" ] && [ "$need" -le "$w1" ]; then
      title_l1="${title_l1:+$title_l1 }$word"
    else
      title_l2="${title_l2:+$title_l2 }$word"
    fi
  done
  [ "${#title_l2}" -gt "$TITLE_WIDTH" ] && title_l2="${title_l2:0:TITLE_WIDTH-1}…"
}

report_herdr_tokens() {
  local args=() root file total done_count tasks="" task="" title
  [ -n "${remaining_int:-}" ] && args+=(--token "ctx=${remaining_int}")

  if [ -n "$session_id" ] && [ -n "$cwd" ]; then
    root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
    file="$root/TASKS-$session_id.md"
    if [ -f "$file" ]; then
      total=$(grep -cE '^[[:space:]]*[-*] \[[ xX]\]' "$file")
      done_count=$(grep -cE '^[[:space:]]*[-*] \[[xX]\]' "$file")
      [ "$total" -gt 0 ] && tasks="${done_count}/${total}"
      # Markdown emphasis and code markers stripped: herdr shows tokens as text.
      task=$(grep -m1 -E '^[[:space:]]*[-*] \[ \] ' "$file" | sed -E 's/^[[:space:]]*[-*] \[ \] //; s/[`*_]//g')
    fi
  fi
  if [ -n "$tasks" ]; then args+=(--token "tasks=$tasks"); else args+=(--clear-token tasks); fi
  if [ -n "$task" ]; then args+=(--token "task=$task"); else args+=(--clear-token task); fi

  title=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | jq -r '.result.pane.terminal_title_stripped // empty')
  case "$title" in claude | "claude "*) title="" ;; esac
  wrap_title "$title" $((TITLE_WIDTH - (${#tasks} > 0 ? ${#tasks} + 1 : 0)))
  for t in title_l1 title_l2; do
    if [ -n "${!t}" ]; then args+=(--token "$t=${!t}"); else args+=(--clear-token "$t"); fi
  done

  herdr pane report-metadata "$HERDR_PANE_ID" --source claude-statusline "${args[@]}"
}

if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] && command -v herdr >/dev/null; then
  report_herdr_tokens </dev/null >/dev/null 2>&1 &
  disown
fi

printf "%b\n" "$line"
