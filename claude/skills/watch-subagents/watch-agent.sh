#!/usr/bin/env bash
# Live follower for one subagent's transcript, rendered in a terminal pane.
#
# Usage: watch-agent.sh <transcript> <label> [ansi-colour] [options]
#
#   transcript         the agent's JSONL, or the `output_file` an Agent tool
#                      result reported
#   label              header text, e.g. the agent type. The description from
#                      the transcript's `.meta.json`, when there is one, is
#                      appended to it
#   ansi-colour        SGR code, default 36 (cyan). 35 magenta, 33 yellow, 32 green, 34 blue
#   --quiet            prose only; omit thinking and tool activity
#   --stop-file PATH   the SubagentStop hook writes the agent's
#                      last_assistant_message here when it ends. The viewer
#                      then closes the stream with a footer, and picks it up
#                      again when the file goes away (the agent was resumed)
#   --tag TEXT         prefix every line with TEXT and skip the header and the
#                      pane title, for several viewers sharing one terminal
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
# The pane title (OSC 2) carries the running totals: tool calls, the context
# the last turn read, and the output tokens so far. herdr and tuios show it,
# and it costs the stream no lines.
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

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

file=${1:?transcript path required}
who=${2:?label required}
colour=${3:-36}
shift $(($# < 3 ? $# : 3))
quiet=false stopfile="" tag=""
while [ $# -gt 0 ]; do
  case $1 in
    --quiet) quiet=true ;;
    --stop-file) stopfile=${2:?--stop-file needs a path}; shift ;;
    --tag) tag=${2:?--tag needs a label}; shift ;;
    *) die "watch-agent: unknown option $1" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is not on PATH"

# In a pane this script's stdout is the pty, so tput reports the real width.
# The fallback covers a viewer whose output is redirected to a file.
cols=$(tput cols 2>/dev/null)
[ "${cols:-0}" -gt 0 ] 2>/dev/null || cols=100

# Claude Code writes the meta file beside the transcript as the agent starts,
# which can be a moment after SubagentStart fires.
desc=""
case $file in
  *.jsonl)
    meta=${file%.jsonl}.meta.json
    for _ in 1 2 3 4 5 6; do [ -r "$meta" ] && break; sleep 0.5; done
    [ -r "$meta" ] && desc=$(jq -r '.description // empty | gsub("\\s+"; " ")' "$meta" 2>/dev/null)
    ;;
esac
label="$who${desc:+ · $desc}"
[ ${#label} -gt $((cols - 8)) ] && label="${label:0:$((cols - 9))}…"

if [ -n "$tag" ]; then
  printf '\033[%sm%s\033[0m \033[2m%s\033[0m\n' "$colour" "$tag" "${desc:-$who}"
else
  printf '\033]2;%s\007' "$label"
  printf '\033[1;%sm=== %s ===\033[0m\n\n' "$colour" "$label"
fi
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
  def num: if type == "number" then . else 0 end;

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
        (.message?.id // .requestId // "?" | s) as $mid
        | (
          # context read and output written by this turn, for the pane title
          ( .message?.usage? | select(type == "object")
            | "U\t\($ts)\t\($mid)\t\((.input_tokens | num) + (.cache_read_input_tokens | num) + (.cache_creation_input_tokens | num))\t\(.output_tokens | num)" ),
          # one turn spans several records, each repeating the turn's usage, so
          # the count carries its turn id for awk to collapse on
          ( ((.message?.usage?.output_tokens_details?.thinking_tokens // 0)
             | if type == "number" then . else 0 end) as $tok
            | if $tok > 0 and thinking_prose == 0
              then "K\t\($ts)\tthought \($tok) tokens\t\($mid)"
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
  | select($quiet == false or startswith("P") or startswith("U"))
JQ

# Compile the filter once, loudly. A syntax error here must not vanish into the
# stderr the pipeline below discards.
printf '' | jq -R --argjson quiet "$quiet" "$filter" >/dev/null \
  || die "watch-agent: jq filter failed to compile"

read -r -d '' painter <<'AWK' || true
  BEGIN {
    sep = sprintf("%c", 1); width = cols + 0
    pre = tag == "" ? "" : tint(tag) " "
    indent = sprintf("%" (11 + (tag == "" ? 0 : length(tag) + 1)) "s", "")
  }
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
  # tool names in one fixed-width column, so the arguments line up. The
  # default width fits every built-in tool; MCP names lose their mcp__
  # prefix (mcp__fff__grep -> fff:grep) and the final report reads as handback.
  function short(s) {
    if (s == "SubagentHandback") return "handback"
    if (sub(/^mcp__/, "", s)) sub(/__/, ":", s)
    return s
  }
  function fixed(s, n) { return length(s) > n ? clip(s, n) : s sprintf("%" (n - length(s)) "s", "") }
  function human(n) { return n >= 1000000 ? sprintf("%.1fM", n / 1000000) : n >= 1000 ? sprintf("%.1fk", n / 1000) : n "" }
  function secs(t,   a) { split(t, a, ":"); return a[1] * 3600 + a[2] * 60 + a[3] }
  function count(n, what) { return (n + 0) " " what (n == 1 ? "" : "s") }
  function title(s) { if (tag == "") printf "\033]2;%s\007", s }
  function totals() {
    title(label " · " count(tools, "tool") (ctx ? " · " human(ctx) " ctx" : "") (outtok ? " · " human(outtok) " out" : ""))
  }
  function norm(s) { gsub(sep, " ", s); gsub(/[ \t\r\n]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
  function prose(ts, body) {
    gsub(sep, "\n", body); gsub("\n", "\n" indent, body)
    printf "%s%s %s %s\n\n", pre, dim(ts), tint("\342\226\270"), body; fflush()
  }

  $2 ~ /^[0-9][0-9]:/ { if (first == "") first = $2; last = $2 }

  $1 == "U" { if ($5 + 0 > seen[$3]) { outtok += $5 - seen[$3]; seen[$3] = $5 + 0 }
              if ($4 + 0 > 0) ctx = $4 + 0
              totals(); fflush(); next }
  $1 == "P" { lastprose = $3; prose($2, $3); next }
  $1 == "K" { if ($4 != "" && $4 == lastturn) next
              if ($4 != "") lastturn = $4
              gsub(sep, "\n" indent, $3)
              printf "%s%s %s %s\n", pre, dim($2), tint("\342\227\207"), think($3); fflush(); next }
  # one tool call is one line: "HH:MM:SS " + marker + " " + name + " " is 12
  # columns of prefix plus the name column, and the argument gets what is left
  $1 == "T" { tools++
              budget = pane_width() - 12 - toolw - (tag == "" ? 0 : length(tag) + 1)
              if (budget < 24) budget = 24
              printf "%s%s %s %s %s\n", pre, dim($2), tint("\302\267"), tool(fixed(short($3), toolw)), dim(clip($4, budget))
              totals(); fflush(); next }
  $1 == "E" { errors++
              printf "%s%s %s %s\n", pre, dim($2), bad("\342\234\227"), bad($3); fflush(); next }

  # Reached when the stop file closed the stream. The final message is shown
  # only when the transcript had not already carried it: the hook's copy is
  # authoritative, the transcript may lag it.
  END {
    if (stopfile == "") exit
    msg = ""; n = 0
    while ((getline line < stopfile) > 0) msg = msg (n++ ? "\n" : "") line
    close(stopfile)
    if (norm(msg) != "" && norm(msg) != norm(lastprose)) prose(last == "" ? "        " : last, msg)
    took = ""
    if (first != "") { d = secs(last) - secs(first); if (d < 0) d += 86400
                       took = " · " (d >= 60 ? int(d / 60) "m" sprintf("%02d", d % 60) "s" : d "s") }
    printf "%s%s\n", pre, tint("\342\234\223 finished" took " · " count(tools, "tool") \
      (errors ? " · " count(errors, "error") : "") (outtok ? " · " human(outtok) " out" : ""))
    title("\342\234\223 " label)
    fflush()
  }
AWK

render() {
  jq -R --unbuffered -r --argjson quiet "$quiet" "$filter" 2>/dev/null \
    | awk -F'\t' -v c="$colour" -v cols="$cols" -v toolw="${WATCH_AGENT_TOOL_WIDTH:-10}" \
        -v tag="$tag" -v label="$label" -v stopfile="$stopfile" "$painter"
}

if [ -z "$stopfile" ]; then
  tail -F -n +1 "$file" 2>/dev/null | render
  exit
fi

# With a stop file, tail runs on its own into a fifo, so it can be killed once
# the agent ends: jq and awk then see EOF, and awk's END prints the footer.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/watch-agent.XXXXXX") || die "watch-agent: mktemp failed"
tailpid=""
trap '[ -n "$tailpid" ] && kill "$tailpid" 2>/dev/null; rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM HUP
fifo=$tmp/feed
mkfifo "$fifo" || die "watch-agent: mkfifo failed"

size() { local n; n=$(wc -c <"$file" 2>/dev/null) || n=0; echo $((n + 0)); }
# The hook can fire before the agent's last records reach the transcript.
settle() {
  local prev=-1 now _
  for _ in 1 2 3 4 5 6; do
    now=$(size); [ "$now" = "$prev" ] && return
    prev=$now; sleep 1
  done
}

offset=0
while :; do
  tail -F -c "+$((offset + 1))" "$file" 2>/dev/null >"$fifo" &
  tailpid=$!
  render <"$fifo" &
  renderpid=$!
  until [ -e "$stopfile" ] || ! kill -0 "$renderpid" 2>/dev/null; do sleep 1; done
  [ -e "$stopfile" ] || die "watch-agent: the stream ended unexpectedly"
  settle
  offset=$(size)
  kill "$tailpid" 2>/dev/null
  wait "$tailpid" 2>/dev/null
  tailpid=""
  wait "$renderpid" 2>/dev/null

  # SubagentStart removes the stop file when the same agent is resumed.
  while [ -e "$stopfile" ]; do sleep 2; done
  printf '\n\033[%sm↻ resumed\033[0m\n\n' "$colour"
done
