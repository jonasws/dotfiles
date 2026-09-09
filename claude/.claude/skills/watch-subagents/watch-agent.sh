#!/usr/bin/env bash
# Live follower for one subagent's transcript, rendered in a terminal pane.
#
# Usage: watch-agent.sh <transcript.output> <label> [ansi-colour] [--quiet]
#
#   transcript.output  the `output_file` path an Agent tool result reported
#   label              header text, e.g. the agent type
#   ansi-colour        SGR code, default 36 (cyan). 35 magenta, 33 yellow, 32 green, 34 blue
#   --quiet            prose only; omit the tool activity
#
# What the stream carries, and why:
#   prose        what the agent concluded — the reason you are watching
#   tool + arg   what it is doing right now, with the salient argument (which
#                file, which pattern, which command), so progress is legible
#                without opening anything
#   errors       a failed tool call is the signal that the agent is stuck
#
# What it deliberately drops: tool result bodies (they are the bulk of the
# transcript and unreadable at speed), and every non-assistant bookkeeping
# record. The transcript itself never enters the orchestrating agent's context.
set -u

file=${1:?transcript path required}
who=${2:?label required}
colour=${3:-36}
quiet=false
[ "${4:-}" = "--quiet" ] && quiet=true

printf '\033[1;%sm=== %s ===\033[0m\n\n' "$colour" "$who"
[ -e "$file" ] || printf '\033[33mwaiting for %s\033[0m\n' "$file"

# jq emits TAG<TAB>time<TAB>body; awk paints it. Keeping the escapes out of jq
# means the filter stays readable and portable.
read -r -d '' filter <<'JQ' || true
  def clip($n): if (. | length) > $n then .[0:$n] + "..." else . end;
  def oneline: gsub("\\s+"; " ");

  def arg($t; $i):
    if   $t == "Read"        then ($i.file_path // "") + (if $i.offset then ":\($i.offset)" else "" end)
    elif $t == "Edit"        then ($i.file_path // "")
    elif $t == "Write"       then ($i.file_path // "")
    elif $t == "NotebookEdit" then ($i.notebook_path // "")
    elif $t == "Bash"        then ($i.command // "" | oneline)
    elif $t == "Grep"        then "\"\($i.pattern // "")\"" + (if $i.path then " in \($i.path)" else "" end)
    elif $t == "Glob"        then ($i.pattern // "")
    elif $t == "Agent"       then ($i.description // "")
    elif $t == "Skill"       then ($i.skill // "")
    elif $t == "WebFetch"    then ($i.url // "")
    elif $t == "WebSearch"   then ($i.query // "")
    elif $t == "TodoWrite"   then "\(($i.todos // []) | length) items"
    else (($i // {}) | keys | join(",")) end;

  (fromjson? // empty)
  | ((.timestamp // "") | if length > 0 then .[11:19] else "        " end) as $ts
  | if .type == "assistant" then
      (.message.content // [])[]
      | if .type == "text" and ((.text // "") | length) > 0 then
          "P\t\($ts)\t\(.text)"
        elif .type == "tool_use" then
          "T\t\($ts)\t\(.name)\t\(arg(.name; .input) | oneline | clip(140))"
        else empty end
    elif .type == "user" then
      (.message.content // [])[]
      | select(.type == "tool_result" and (.is_error // false))
      | "E\t\($ts)\t\((.content | if type == "array" then (map(.text? // "") | join(" ")) else (. // "" | tostring) end) | oneline | clip(160))"
    else empty end
JQ

if [ "$quiet" = true ]; then
  filter="$filter"' | select(startswith("P"))'
fi

tail -F -n +1 "$file" 2>/dev/null \
  | jq -R --unbuffered -r "$filter" \
  | awk -F'\t' -v c="$colour" '
      function dim(s)  { return "\033[2m"  s "\033[0m" }
      function tint(s) { return "\033[" c "m" s "\033[0m" }
      function tool(s) { return "\033[33m" s "\033[0m" }
      function bad(s)  { return "\033[31m" s "\033[0m" }
      $1 == "P" { printf "%s %s %s\n\n", dim($2), tint("\342\226\270"), $3; fflush(); next }
      $1 == "T" { printf "%s %s %s %s\n",  dim($2), tint("\302\267"), tool($3), dim($4); fflush(); next }
      $1 == "E" { printf "%s %s %s\n",     dim($2), bad("\342\234\227"), bad($3); fflush(); next }
    '
