# agent-sessions

Every coding-agent session on this machine, across repositories and harnesses,
with the tuios pane each one runs in. `agent-sessions.nu` is the CLI behind the
`agent-sessions` television channel (`tv agent-sessions`, F6) and the Raycast
script command in `~/dotfiles/raycast/scripts/agent-session.sh`.

## Where the data comes from

- **Adapters list the sessions.** One per harness, in `adapters/`. Each reads
  its harness's own record of past sessions, so a session shows up whether or
  not it is open anywhere.
- **tuios marks the live ones.** `tuios list-agents --all-sessions` reports
  `harness_id` and `agent_session_id` for every agent pane. Together they make
  the session key, so a row knows its pane exactly. tuios keeps no history of
  closed conversations, so it can only overlay, never list.

## CLI

```
agent-sessions.nu list [all|live|here|<harness>] [--json]
agent-sessions.nu find [words...] [--json]       newest session matching every word
agent-sessions.nu info <key> [--json]
agent-sessions.nu get <key> <field>              id cwd title transcript resume pane key
agent-sessions.nu copy <key> <field>
agent-sessions.nu preview <key> [chat|reply|activity|pane]
agent-sessions.nu open <key> [--fork] [--dry-run]
```

A key is `<harness>:<session id>`, with tuios's harness ids (`claude-code`,
`pi`, `codex`, ...). `here` is the repository the command runs in and all its
worktrees. `--json` output is the adapter record plus `key` and `pane` (null
when no pane runs it), which is what a Raycast extension or another tool reads.

`open`:

1. A pane runs the session: focus it and switch the client to its tuios
   session.
2. A pane holds the session but its agent exited (a shell at its prompt, or a
   pane a daemon restart brought back): focus it and run `tuios resume-agent`
   there. tuios builds the command from the harness manifest and the flags
   the agent was started with (model, effort, permission mode), and types it
   into the pane's shell. `tuios list-agents --all` reports such panes with
   the conversation id and an empty harness, so one call finds them.
3. Otherwise, inside tuios (or with `AGENT_SESSIONS_TUIOS=1`): open the
   repository's tuios session with `../tuios-session.sh`, which finds or
   creates it and names a worktree's session as tuios does, then open a pane
   there with `tuios new-window ... -- fish -C '<resume command>'`. The pane
   outlives the agent and shows why a resume failed, the agent reports its
   own conversation id through its hooks (so the pane becomes case 2 once it
   exits), and new-window returns at once, so the picker's popup closes
   before the agent starts. `tuios start-agent` is for an agent starting a
   helper: it waits until the helper is ready and makes it the caller's
   child, neither of which a resumed conversation wants. `resume-agent`
   cannot serve here, since storing an id on another pane
   (`set-agent-session -w`) needs the respond grant.
4. Outside tuios: `cd` to the directory and exec the resume command.

When the session's directory was removed, `open` first recreates it as a
worktree of the session's branch (`git worktree add`), from the nearest
ancestor that is a repository or the checkout a `.../worktrees/<repo>/...`
path names. It refuses when the branch is gone. `--dry-run` prints the plan.

## Writing an adapter

An adapter is an executable at `adapters/<harness id>.<ext>`; the file's stem
must be the harness id tuios uses, or live panes will not match. It answers
three commands and writes JSON to stdout, one object per line. Exit non-zero
for an unknown id.

`list` and `info <id>` print session records:

| field          | type            |                                                        |
| -------------- | --------------- | ------------------------------------------------------ |
| `harness`      | string          | the harness id, same as the file stem                  |
| `id`           | string          | what the harness resumes by and tuios records          |
| `title`        | string          | one line                                               |
| `first_prompt` | string          | one line                                               |
| `cwd`          | string          | directory the session runs in; resume starts there     |
| `branch`       | string          | git branch, `""` when unknown                          |
| `created`      | int ms \| null  | epoch milliseconds                                     |
| `updated`      | int ms          | last activity; rows sort on it                         |
| `size`         | int \| null     | transcript bytes                                       |
| `transcript`   | string          | path of the file the session is read from              |
| `resume`       | string[]        | argv that resumes it in `cwd`                          |
| `fork`         | string[] \| null| argv that resumes it as a new session, null if none    |

`messages <id>` prints the conversation in order, harness noise left out:

```json
{"role": "user|assistant", "text": "...", "tools": [{"name": "Edit", "hint": "one line", "file": "/abs/path"}], "at": "ISO time"}
```

`file` is optional and feeds the files list of the `activity` preview; tool
names are compared case-insensitively (`edit`, `write`, `read`).

`list` runs on every picker open, so keep it under half a second. All adapters
run in parallel and one that fails is skipped.

## Adapters

- `claude-code.ts`: the Claude Agent SDK's `listSessions()`,
  `getSessionInfo()` and `getSessionMessages()`, rather than parsing
  `~/.claude/projects/*.jsonl`, whose format is internal. bun installs the
  pinned SDK version into its cache on first run.
- `pi.nu`: reads `~/.pi/agent/sessions/**/*.jsonl` (`AGENT_SESSIONS_PI_DIR`
  overrides). Written to pi's documented layout and tested only on a synthetic
  file; check it against a real session before relying on it.

Candidates: atuin's thread index (`atuin threads list --style ndjson`) already
covers claude-code, codex, opencode and pi in one place and would make a single
adapter for all of them, once its daemon runs.
