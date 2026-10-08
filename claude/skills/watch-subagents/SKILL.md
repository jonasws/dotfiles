---
name: watch-subagents
description: Open a Herdr pane per running subagent showing that agent's live activity - prose, thinking, tool calls with their arguments, and errors or denials. Use when the user asks to watch, tail, follow or see what subagents are doing, or wants a live view of background agent progress. Requires HERDR_ENV=1.
---

# Watch subagents

Give each running subagent its own pane, in a tab named `subagents`, showing
what it is doing, live.

A subagent's transcript is a JSONL file far too large to read into the
orchestrating context. Streaming a projection of it into a pane puts the
progress in front of the user at no context cost.

## When to use

The user asks to watch, tail, follow, or see subagent progress — during a long
review, a parallel investigation, or any `Agent` call running in the background.

Skip it for a single fast subagent: the pane costs more attention than the wait.

## What the stream carries

Four event kinds, one line each, oldest first:

| Marker | Event | Why it earns a line |
| --- | --- | --- |
| `▸` | the agent's prose | what it concluded — the reason you are watching |
| `◇` | its thinking | the pause before a tool call reads as deliberation, not as a hang |
| `·` | a tool call, with its salient argument | what it is doing right now: which file, which pattern, which command |
| `✗` | a failed or denied tool call | the signal that the agent is stuck, or waiting on the user |

Each line is timestamped dim-grey. The salient argument is extracted per tool —
`file_path` for Read/Edit/Write, `command` for Bash, `pattern` (+ `path`) for
Grep, `url` for WebFetch, `description` for a nested Agent.

A tool call is legible only while it stays on one line, so its argument is
clipped to the pane's own width rather than to a fixed budget: each viewer holds
a fraction of the window, and that fraction shrinks every time another agent's
pane is split off beside it. The viewer re-measures as it runs, so a pane that
narrows mid-flight keeps its lines short. The other three kinds soft-wrap
instead — they are rare, and their tails carry the point.

Thinking almost never survives to disk: the block is written, but its `.thinking`
is empty and only the signature remains. The `◇` line is therefore usually the
turn's `thinking_tokens` count — `thought 55 tokens` — and carries the prose only
on the rare transcript that kept it. A turn spans several records that each
repeat the same usage figures, so the count is collapsed to one line per turn.

A denial is reported as `denied (user-rejected)` rather than as the paragraph of
boilerplate its tool result carries. An agent stopped at a permission prompt
otherwise looks exactly like an idle one.

Deliberately dropped: tool *result* bodies, which are the bulk of the transcript
and unreadable at speed, and every non-assistant bookkeeping record.

Prose spanning several lines is shown whole, indented under its timestamp. The
transcript's records are heterogeneous — `.message.content` is an array on most
and a bare string on others, a record tailed mid-write is not JSON yet — so the
viewer coerces what it can and silently skips what it cannot. A record it does
not understand costs one line, never the stream.

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

2. **Create or reuse the `subagents` tab.** Viewers never split the caller's
   pane. They live in a tab of their own, so the user's working pane keeps its
   full width however many agents run, and the tab bar names where they went.

   ```bash
   herdr tab list --workspace "$HERDR_WORKSPACE_ID"
   ```

   Reuse a tab whose `label` ends in `subagents` if one is already listed.
   `tab list` renders labels with a `[N] ` index prefix — the tab created below
   comes back as `[2] subagents` — so match the suffix, never the whole string.
   Otherwise create it:

   ```bash
   herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" \
     --label subagents --no-focus
   ```

   Read `.result.tab.tab_id` and `.result.root_pane.pane_id`. That root pane is
   a live shell already in `$PWD`, and it holds the first viewer.

3. **Create the remaining panes inside that tab.** The first agent takes the
   root pane, so split only from the second agent on — each split off the pane
   made last, alternating direction so the panes tile rather than collapse into
   slivers:

   ```bash
   herdr pane split --pane <previous-pane-id> --direction right --cwd "$PWD" --no-focus
   ```

   Read the new id from `.result.pane.pane_id`, and alternate `right`, `down`,
   `right`, and so on.

   When reusing a `subagents` tab that already holds viewers, split off one of
   its existing panes instead of the root:

   ```bash
   herdr pane list --workspace "$HERDR_WORKSPACE_ID"
   ```

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

6. **Tell the user the tab is named `subagents`**, which pane in it holds which
   agent, and that Ctrl-C in a pane stops only that viewer.

## Rules

- Never read a transcript into your own context. Bounded `pane read` calls to
  verify rendering are fine; dumping the pane is not.
- Always pass `--no-focus`. The user keeps their pane.
- Always pass `--cwd "$PWD"` so the viewer starts where the user is.
- Do not close panes you did not create. When the agents finish, leave the
  `subagents` tab and its output; say it can be closed with
  `herdr tab close <tab_id>` rather than closing it. A left-open tab is what the
  next run reuses.
- Report the agents' findings from the completion notifications you receive, not
  from what you saw in a pane.
