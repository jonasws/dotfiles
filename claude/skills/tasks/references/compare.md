# The three "task" systems side by side

They share a word and nothing else. Nothing syncs between them except the
user's `tsk-dispatch.sh`, which makes a tuios card titled `T<n>: <title>` for a
tsk task.

| | tsk | tuios task cards | Claude Code Task tools |
|---|---|---|---|
| What it is | The user's backlog, shared across every repo and session | One run of work in a tuios session, held by a pane | One session's checklist, or an agent team's shared list |
| Lives in | The tsk store (`~/.tsk`), scoped to a project (a git repo root, so a worktree is its own) or the desk | The tuios daemon, per session; survives the pane closing | The Claude session |
| Statuses | open → ready → started → blocked / review → done | todo → plan → doing → verify → review → shipped → done | pending → in progress → completed |
| Who sets done | Only the user | The user (`done`), or a merged PR (`shipped`) | The session |
| Dependencies | `tsk edit T13 --after T12` holds T13 until T12 is done | `tuios task block ID REASON` / `--clear` | blocked-by within the list |
| Hands out work | `tsk dispatch` (Herdr only) | `task claim --next`, dispatch, `fan --task` | the lead assigns, teammates claim |
| Moves on its own | no | a plan held, a fan verify, a PR opening or merging on the worktree branch | no |
| Commands | `tsk-cli` skill | `tuios --skill tasks` | built in (`TaskCreate` …), on by default only for older models |

## When a tuios card is in play

- If you hold a card (`tuios task ls` shows your pane), `tuios task block ID
  REASON` when stuck, and `tuios task done ID` when your part is finished. That
  sends it to verify or review; it does not close it.
- Cards come back after a daemon restart with no holder.
- `tuios --skill tasks` documents verify commands, auto-dispatch and stages.

## Worktree commands at a glance

| Command | Makes | Notes |
|---|---|---|
| `tuios worktree new <branch> [--agent claude] [--setup CMD]` | worktree + session | `worktree ls` shows them with agent state; `worktree diff <session>` |
| `tuios fan N --agent claude --repo DIR [--name STEM] [--task CARD] PROMPT` | N worktrees + sessions | `fan compare`, `fan verify <s> -- CMD`, `fan diff A B`, `fan keep <s>` |
| `tuios delegate --isolation worktree [--wait 10m] PROMPT` | one child worktree + session | answer arrives as mail, or inline with `--wait` |
| `tuios start-agent claude --cwd DIR --name NAME --prompt …` | no worktree | a new agent pane in an existing folder |
