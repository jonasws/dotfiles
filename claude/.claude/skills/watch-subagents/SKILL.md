---
name: watch-subagents
description: Open a Herdr pane per running subagent showing that agent's live activity - prose, tool calls with their arguments, and errors. Use when the user asks to watch, tail, follow or see what subagents are doing, or wants a live view of background agent progress. Requires HERDR_ENV=1.
---

# Watch subagents

Give each running subagent its own terminal pane showing what it is doing, live.

A subagent's transcript is a JSONL file far too large to read into the
orchestrating context. Streaming a projection of it into a pane puts the
progress in front of the user at no context cost.

## When to use

The user asks to watch, tail, follow, or see subagent progress — during a long
review, a parallel investigation, or any `Agent` call running in the background.

Skip it for a single fast subagent: the pane costs more attention than the wait.

## What the stream carries

Three event kinds, one line each, oldest first:

| Marker | Event | Why it earns a line |
| --- | --- | --- |
| `▸` | the agent's prose | what it concluded — the reason you are watching |
| `·` | a tool call, with its salient argument | what it is doing right now: which file, which pattern, which command |
| `✗` | a failed tool result | the signal that the agent is stuck |

Each line is timestamped dim-grey. The salient argument is extracted per tool —
`file_path` for Read/Edit/Write, `command` for Bash, `pattern` (+ `path`) for
Grep, `url` for WebFetch, `description` for a nested Agent — and clipped.

Deliberately dropped: tool *result* bodies, which are the bulk of the transcript
and unreadable at speed, and every non-assistant bookkeeping record.

## Prerequisites

```bash
test "${HERDR_ENV:-}" = 1
```

If that fails, say the session is not running inside Herdr and stop. `jq` must
also be on `PATH`.

## Procedure

1. **Collect one transcript path per agent.** Every `Agent` tool result reports
   an `output_file`. Use those paths verbatim. Never `Read` or `tail` them
   yourself — that is the whole point of the pane.

   For an agent whose result you no longer have, take the newest files in the
   session's tasks directory:

   ```bash
   ls -t "$(dirname "$TMPDIR")"/*/*/tasks/*.output 2>/dev/null | head -5
   ```

2. **Check the caller's geometry**, so the split does not produce a sliver:

   ```bash
   herdr pane layout --pane "$HERDR_PANE_ID"
   ```

   Split a wide pane `right`, a narrow or tall one `down`. For N agents, split
   once off the caller, then stack the rest `down` off that new pane.

3. **Create one pane per agent**, keeping the user's focus where it is:

   ```bash
   herdr pane split --current --direction right --cwd "$PWD" --no-focus
   ```

   Read the id from `.result.pane.pane_id`. For the next agent, split `down`
   off that id rather than off the caller again.

4. **Start one viewer per pane**, each in its own colour:

   ```bash
   herdr pane run <pane-id> "clear; bash ~/.claude/skills/watch-subagents/watch-agent.sh <output_file> '<label>' 36"
   ```

   Colours: 36 cyan, 35 magenta, 33 yellow, 32 green, 34 blue. Use the agent
   type as the label. Append `--quiet` as a fourth argument for prose only,
   when tool activity would be noise rather than life.

5. **Confirm each pane renders** with a small bounded read — a few lines, never
   the whole pane:

   ```bash
   herdr pane read <pane-id> --source recent-unwrapped --lines 3
   ```

6. **Tell the user which pane holds which agent**, and that Ctrl-C in a pane
   stops only that viewer.

## Rules

- Never read a transcript into your own context. Bounded `pane read` calls to
  verify rendering are fine; dumping the pane is not.
- Always pass `--no-focus`. The user keeps their pane.
- Always pass `--cwd "$PWD"` so the viewer starts where the user is.
- Do not close panes you did not create. When the agents finish, leave the panes
  and their output; say they can be closed rather than closing them.
- Report the agents' findings from the completion notifications you receive, not
  from what you saw in a pane.
