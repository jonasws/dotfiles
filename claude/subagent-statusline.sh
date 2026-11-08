#!/bin/sh
# subagentStatusLine for Claude Code: one row per subagent in the panel under
# the prompt. Claude Code sends every visible row on stdin once per refresh
# tick and draws each {"id","content"} line written back in place of its own
# `name · description · tokens` row.
# https://code.claude.com/docs/en/statusline#subagent-status-lines
#
#   ● Explore · Map the hook flow · ▂▅█▃▁▁ 41.2k 21% · sonnet-5-5 high · 3m12s · ⎇ fix-login
#
# The sparkline is the growth of the token count between ticks, not the count
# itself, which only climbs: a run of ▁ is a subagent that has stopped
# producing, which is the thing worth catching from the corner of an eye.
# The worktree shows only when the subagent runs outside the session's folder.
#
# The row is fitted to `columns`: the description is clipped first, and is
# dropped before the figures are.
exec jq -c --unbuffered '
  def human: if . >= 1000000 then "\(. / 100000 | floor / 10)M"
             elif . >= 1000 then "\(. / 100 | floor / 10)k"
             else tostring end;
  def took: (. / 1000 | floor) as $s
    | if $s >= 3600 then "\($s / 3600 | floor)h\($s % 3600 / 60 | floor)m"
      elif $s >= 60 then "\($s / 60 | floor)m\($s % 60)s"
      else "\($s)s" end;
  def spark:
    [range(1; length) as $i | .[$i] - .[$i - 1] | if . < 0 then 0 else . end] as $d
    | ($d | max // 0) as $top
    | $d | map(if . == 0 then "▁"
               else ["▂", "▃", "▄", "▅", "▆", "▇", "█"][(. / $top * 7 | ceil) - 1 | if . > 6 then 6 else . end]
               end)
    | join("");
  def clip($n): if length > $n then .[0:$n - 1] + "…" else . end;
  def dim: "\u001b[2m" + . + "\u001b[0m";

  . as $in
  | (($in.columns // 80) | if type == "number" then . else 80 end) as $cols
  | (now * 1000) as $now
  | $in.tasks[]?
  | . as $t
  | ({running: "\u001b[36m●\u001b[0m", completed: "\u001b[32m✓\u001b[0m",
      failed: "\u001b[31m✗\u001b[0m", killed: "\u001b[2m■\u001b[0m"}[$t.status // ""]
      // "\u001b[2m○\u001b[0m") as $mark
    | ($t.name // $t.agentType // "agent") as $who
    | (($t.label // $t.description // "") | gsub("\\s+"; " ")) as $what
    | ([ ([($t.tokenSamples // []) | spark | select(length > 0)]
          + [($t.tokenCount // 0) | human]
          + [if ($t.contextWindowSize // 0) > 0
             then "\(($t.tokenCount // 0) * 100 / $t.contextWindowSize | floor)%" else empty end]
          | join(" ")),
         ([($t.model // "" | sub("^claude-"; "") | sub("-[0-9]{8}$"; "") | sub("\\[.*\\]$"; "")
            | select(length > 0))]
          + [$t.effort // empty | tostring] | join(" ") | select(length > 0)),
         (if $t.startTime then $now - $t.startTime | took else empty end),
         (if ($t.cwd // "") != "" and $t.cwd != ($in.cwd // "")
          then "⎇ " + ($t.cwd | split("/") | last) else empty end)
       ] | join(" · ")) as $figures
    | ($cols - ($who | length) - ($figures | length) - 8) as $room
    | {id: $t.id,
       content: ("\($mark) \($who)"
         + (if $room >= 8 and ($what | length) > 0 then " · " + ($what | clip($room)) else "" end)
         + (" · " + $figures | dim))}
'
