---
name: tasks
description: Picks the right tool before starting, handing off, isolating or tracking a piece of work, where tsk, tuios and Claude Code each offer a competing "task" or "worktree". Use whenever work is about to be deferred, split off, started in parallel, handed to another agent, or moved into a worktree; when the user says "start T12", "in a worktree", "fan out", "delegate", "spin up an agent", "task card", "background this", or asks where a worktree went or how to clean one up; and before calling EnterWorktree, `claude --worktree`, an Agent with `isolation: worktree`, `tsk dispatch`, `tuios worktree`, `tuios fan` or `tuios delegate`. For the tsk commands themselves, it hands off to the `tsk-cli` skill.
---

# Tasks and worktrees

Three tools each have a "task" and a way to make a worktree, and they share the
words without sharing anything else: tsk (the board), tuios (task cards,
worktree sessions, agents) and Claude Code (its own worktrees and subagents).
Picking the wrong one leaves a worktree no cleanup knows about, a task on a
board nobody looks at, or a branch missing the commits it needed.

The rule that settles most cases: **tsk records the work, tuios runs it.**
Inside tuios (`TUIOS_ENV=1`, the normal case) prefer tuios for every agent,
worktree and hand-off. Claude Code's own worktrees are for sessions outside
tuios.

## Routing

| The work | Use | Not |
|---|---|---|
| Outlives this session: deferred, split off, found along the way | tsk: `tsk add`. Load `tsk-cli` for the commands | a tuios card, or a note in chat |
| Pick up a tsk task here, in this folder | `tsk status T<n> started --no-dispatch`, then work it | `tsk dispatch` |
| Start a tsk task in another agent, same folder | `prefix+ctrl+s` on the board (`tsk-dispatch.sh here`) | `tsk dispatch` |
| Start a tsk task in its own worktree | `prefix+S` on the board (`tsk-dispatch.sh worktree`, a `tuios fan 1`); the script marks the task started itself | `tsk dispatch`, `EnterWorktree`, a `tsk status` first |
| A worktree with no tsk task | `tuios worktree new <branch> [--agent claude]` | `git worktree add`, `EnterWorktree` |
| Several attempts at the same problem | `tuios fan N`, then `fan compare` / `fan verify` / `fan keep` | several `worktree new` by hand |
| Hand a subtask to another agent and get the answer back | `tuios delegate` (`--isolation worktree` when it edits in parallel with you) | an Agent with `isolation: worktree` |
| A short mechanical subtask in this conversation (`implementer`, `Explore`, `researcher`) | the Agent tool, no isolation | `tuios delegate` (overkill) |
| Track the order of steps inside one task | `tsk steps` on that task | Claude Code's Task tools (absent on this model) |
| Outside tuios entirely (plain terminal, Herdr) | Claude Code's `--worktree` / `EnterWorktree`, or `tsk dispatch` in Herdr | tuios commands |

The board keys are `[[keybindings.command]]` entries in
`~/dotfiles/tuios/config.toml`, which `tuios keybinds explain` and `keybinds
list` do not report (they show `prefix+S` as free). Confirm one with
`rg -n -A3 'tsk-dispatch' ~/dotfiles/tuios/config.toml` before naming it.

## Where worktrees go

Each tool keeps its own; none of them sees the others'.

| Made by | Path | Base |
|---|---|---|
| tuios (`worktree new`, `fan`, `delegate --isolation worktree`, `prefix+S`) | `../.worktrees/<repo>/<branch-slug>` beside the repo, e.g. `~/CX/.worktrees/cn-cx-booking-service/tsk-t161-split-pool` | the main checkout's HEAD |
| `tsk dispatch` (Herdr only) | `~/.herdr/worktrees/<repo>/…` | the task's `--base`, else the default branch |
| Claude Code (`--worktree`, `EnterWorktree`, Agent `isolation: worktree`) | `<repo>/.claude/worktrees/<name>`, branch `worktree-<name>` | HEAD (`worktree.baseRef: "head"` in settings) |

tuios puts worktrees beside the repo, not under `~/.local/share/tuios`, so a
worktree of a repo in `~/CX`, `~/CNOPS` or `~/CN-TERMINAL` still loads that
folder's `CLAUDE.md` and stays inside the sandbox's writable paths. Every tuios
worktree is its own **session** named `<repo>-<branch>`, grouped under the repo
on the rail; there is no "new workspace in this session" option. Its
`after-new-worktree` hook (`tuios/scripts/new-worktree.sh`) links the main
checkout's git-ignored `.mise.local.toml` in, trusts mise and installs tools
before the first pane starts.

## What travels into a worktree, and what does not

- **Committed work only.** tuios and Claude Code branch from HEAD; uncommitted
  changes stay behind. Commit (or stash and re-apply) before `fan` or
  `worktree new` if the new agent needs them.
- **Not the tsk task.** A worktree is a tsk project of its own, and `tsk list`
  there is empty. The main checkout owns the task: start it there, put the
  notes in the worktree agent's prompt (as `tsk-dispatch.sh` does), and let the
  worktree agent report through its pull request. Never `-p` back to the main
  board from a worktree.
- **Not other git-ignored files.** Only `.mise.local.toml` is linked by the
  hook. Anything else local (an `.env`, a `local.properties`) has to be linked
  or copied by hand, or added to the hook.

## Cleaning up

Clean a worktree with the tool that made it; the others refuse or leave a stale
record behind.

| Made by | Remove with |
|---|---|
| tuios worktree / delegate | `tuios worktree rm <session>` (`--stash` keeps uncommitted work; the branch is kept) |
| tuios fan | `tuios fan keep <session>` removes the other attempts |
| tsk dispatch | `tsk clean T<n>`, or `tsk status T<n> done --clean` when the user said done |
| Claude Code | its exit prompt, or `git worktree remove` |
| anything removed by hand | `git worktree prune` to drop git's record |

Removing a worktree is the user's call unless they asked for it; say which
command you would run.

## Avoid

- **`tsk dispatch`, or `tsk status … started` without `--no-dispatch`, from
  tuios.** Both need Herdr: you get `not-in-herdr`, or the task marked started
  with no agent behind it.
- **`EnterWorktree` / `claude --worktree` inside a tuios worktree session.** It
  nests a second worktree under `.claude/worktrees/` of the first, which no
  cleanup expects.
- **Treating a tuios card's `done` as tsk's `done`.** `tuios task done` only
  lets the card go to verify or review. tsk `done` is the user's.
- **Writing to tsk from a subagent or a worktree agent.** Only the main agent in
  the main checkout writes to the board; the others report back.
- **Assuming a worktree agent reads that worktree's `CLAUDE.md`.** An Agent
  subagent gets the parent conversation's instructions. A tuios worktree agent
  is a fresh session and does read it.

For the three "task" systems side by side (statuses, dependencies, who hands
out work), read [references/compare.md](references/compare.md).
