#!/usr/bin/env bash
# Live follower for one subagent's transcript, rendered in a terminal pane.
#
# Usage: watch-agent.sh <transcript.output> <label> [ansi-colour] [--quiet]
#
#   transcript.output  the `output_file` path an Agent tool result reported
#   label              header text, e.g. the agent type
#   ansi-colour        SGR code, default 36 (cyan). 35 magenta, 33 yellow, 32 green, 34 blue
#   --quiet            prose only; omit thinking and tool activity
#
# What the stream carries, and why:
#   prose        what the agent concluded — the reason you are watching
#   thinking     how much it deliberated before acting, so a long pause reads as
#                thought rather than as a hang
#   tool + arg   what it is doing right now, with the salient argument (which
#                file, which pattern, which command), so progress is legible
#                without opening anything
#   errors       a failed or denied tool call is the signal that the agent is stuck
#
# What it deliberately drops: tool result bodies (they are the bulk of the
# transcript and unreadable at speed), and every non-assistant bookkeeping
# record. The transcript itself never enters the orchestrating agent's context.
#
# A tool call is worth reading only while it stays on one line, so its argument
# is clipped to what the pane can show — measured, not guessed, since a viewer
# gets a third of the window once three agents run and a fixed budget would wrap
# the very lines the clipping exists to keep short. jq bounds the argument only
# so a 26KB command does not cross the pipe; awk, which knows the prefix and the
# tool name, does the fitting. Prose, thinking and errors soft-wrap instead:
# they are rare, and their tails carry the point.
#
# Thinking reaches disk as a block whose `.thinking` is almost always empty —
# the signature survives, the prose does not — so the usual line is the turn's
# `thinking_tokens` count instead. Where the text is present it is shown whole
# and the count suppressed, so one turn never reports its thinking twice.
#
# The transcript is heterogeneous: records carry `type` values this projection
# knows nothing about, `.message.content` is an array of blocks on most records
# and a bare string on others, a tool result's `.content` is either a string or
# a list of blocks, and a line tailed mid-write is not JSON at all. The filter
# therefore coerces every shape it reads and runs inside `try ... catch empty`,
# so an unrecognised record costs one dropped line rather than a jq error
# sprayed into the pane.
set -u

file=${1:?transcript path required}
who=${2:?label required}
colour=${3:-36}
quiet=false
[ "${4:-}" = "--quiet" ] && quiet=true

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is not on PATH"

# In a pane this script's stdout is the pty, so tput reports the real width.
# The fallback covers a viewer whose output is redirected to a file.
cols=$(tput cols 2>/dev/null)
[ "${cols:-0}" -gt 0 ] 2>/dev/null || cols=100

printf '\033[1;%sm=== %s ===\033[0m\n\n' "$colour" "$who"
[ -e "$file" ] || printf '\033[33mwaiting for %s\033[0m\n' "$file"

# jq emits TAG<TAB>time<TAB>body; awk paints it. Keeping the escapes out of jq
# means the filter stays readable and portable. Newlines inside prose become
# U+0001 so one event stays one awk record; awk restores them as indented
# continuation lines, instead of awk dropping every line after the first.
read -r -d '' filter <<'JQ' || true
  def s: if type == "string" then . else tostring end;
  def clip($n): s | if length > $n then .[0:$n] + "..." else . end;
  def oneline: s | gsub("\\s+"; " ");
  def wrapped: s | gsub("\r"; "") | gsub("\n"; "\u0001");
  def solid: s | gsub("\\s"; "") | length > 0;

  # content is an array of blocks, a bare string, or a lone block object
  def blocks:
    if   type == "array"  then .[]
    elif type == "object" then .
    elif type == "string" then {type: "text", text: .}
    else empty end;

  # a tool result's content is a string, or blocks carrying .text
  def result_text:
    if   type == "array"  then (map(.text? // "" | s) | join(" "))
    elif type == "object" then (.text? // "" | s)
    else s end;

  # how many of this record's thinking blocks actually carry prose
  def thinking_prose:
    (.message?.content? | if type == "array" then . else [.] end)
    | map(select(type == "object" and .type? == "thinking" and (.thinking? // "" | solid)))
    | length;

  def arg($t; $in):
    ($in | if type == "object" then . else {} end) as $i
    | if   $t == "Read"         then ($i.file_path // "" | s) + (if $i.offset then ":\($i.offset)" else "" end)
      elif $t == "Edit"         then ($i.file_path // "")
      elif $t == "Write"        then ($i.file_path // "")
      elif $t == "NotebookEdit" then ($i.notebook_path // "")
      elif $t == "Bash"         then ($i.command // "")
      elif $t == "Grep"         then "\"\($i.pattern // "")\"" + (if $i.path then " in \($i.path)" else "" end)
      elif $t == "Glob"         then ($i.pattern // "")
      elif $t == "Agent"        then ($i.description // "")
      elif $t == "Skill"        then ($i.skill // "")
      elif $t == "WebFetch"     then ($i.url // "")
      elif $t == "WebSearch"    then ($i.query // "")
      elif $t == "TodoWrite"    then "\(($i.todos // []) | if type == "array" then length else 0 end) items"
      else ($i | keys | join(",")) end;

  try (
    (fromjson? // empty)
    | select(type == "object")
    | ((.timestamp? // "") | if type == "string" and length > 0 then .[11:19] else "        " end) as $ts
    | if .type == "assistant" then
        (
          # one turn spans several records, each repeating the turn's usage, so
          # the count carries its turn id for awk to collapse on
          ( ((.message?.usage?.output_tokens_details?.thinking_tokens // 0)
             | if type == "number" then . else 0 end) as $tok
            | if $tok > 0 and thinking_prose == 0
              then "K\t\($ts)\tthought \($tok) tokens\t\(.message?.id // .requestId // "?")"
              else empty end ),
          ( (.message?.content? | blocks)
            | select(type == "object")
            | if .type? == "text" and (.text? // "" | solid) then
                "P\t\($ts)\t\(.text | wrapped)"
              elif .type? == "thinking" and (.thinking? // "" | solid) then
                "K\t\($ts)\t\(.thinking | wrapped)"
              elif .type? == "tool_use" then
                "T\t\($ts)\t\(.name // "tool" | oneline)\t\(arg((.name? | s); .input) | oneline | clip(2000))"
              else empty end )
        )
      elif .type == "user" then
        (
          # a denial names itself in one word; its tool_result is a paragraph of
          # boilerplate addressed to the agent, so the record yields one or the
          # other, never both
          ( if (.toolDenialKind? // null) != null
            then "E\t\($ts)\tdenied (\(.toolDenialKind | oneline))"
            else ( (.message?.content? | blocks)
                   | select(type == "object" and .type? == "tool_result" and (.is_error? // false) == true)
                   | "E\t\($ts)\t\(.content | result_text | oneline | clip(600))" ) end )
        )
      else empty end
  ) catch empty
  | select($quiet == false or startswith("P"))
JQ

# Compile the filter once, loudly. A syntax error here must not vanish into the
# stderr the pipeline below discards.
printf '' | jq -R --argjson quiet "$quiet" "$filter" >/dev/null \
  || die "watch-agent: jq filter failed to compile"

tail -F -n +1 "$file" 2>/dev/null \
  | jq -R --unbuffered -r --argjson quiet "$quiet" "$filter" 2>/dev/null \
  | awk -F'\t' -v c="$colour" -v cols="$cols" '
      BEGIN { sep = sprintf("%c", 1); width = cols + 0 }
      function dim(s)   { return "\033[2m"  s "\033[0m" }
      function tint(s)  { return "\033[" c "m" s "\033[0m" }
      function tool(s)  { return "\033[33m" s "\033[0m" }
      function bad(s)   { return "\033[31m" s "\033[0m" }
      function think(s) { return "\033[2;3m" s "\033[0m" }

      # the tab splits a new pane off an existing one for every agent after the
      # first, so a width sampled once at startup is stale by the second agent
      function pane_width(   cmd, out) {
        if (++tick % 25 == 1) {
          cmd = "tput cols 2>/dev/null"
          if ((cmd | getline out) > 0 && out + 0 > 0) width = out + 0
          close(cmd)
        }
        return width
      }
      function clip(s, n) { return length(s) > n ? substr(s, 1, n - 1) "\342\200\246" : s }

      $1 == "P" { gsub(sep, "\n           ", $3)
                  printf "%s %s %s\n\n", dim($2), tint("\342\226\270"), $3; fflush(); next }
      $1 == "K" { if ($4 != "" && $4 == lastturn) next
                  if ($4 != "") lastturn = $4
                  gsub(sep, "\n           ", $3)
                  printf "%s %s %s\n",    dim($2), tint("\342\227\207"), think($3); fflush(); next }
      # one tool call is one line: "HH:MM:SS " + marker + " " + name + " " is 12
      # columns of prefix plus the name, and the argument gets what is left
      $1 == "T" { budget = pane_width() - 12 - length($3)
                  if (budget < 24) budget = 24
                  printf "%s %s %s %s\n",  dim($2), tint("\302\267"), tool($3), dim(clip($4, budget)); fflush(); next }
      $1 == "E" { printf "%s %s %s\n",     dim($2), bad("\342\234\227"), bad($3); fflush(); next }
    '
