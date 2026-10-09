## CLI tool preferences

Prefer these tools over their POSIX equivalents. Examples are load-bearing.

## Search & file tools

Non-default tools; reach for them deliberately. Match tool to question shape, not a fixed order.

| Question shape | Tool |
|---|---|
| Structure on a resolved symbol: who calls X, blast radius, what implements it | `LSP` tool: `findReferences`, `incomingCalls`/`outgoingCalls`, `goToImplementation` |
| "where is X", "how does Y work" — semantic, no exact identifier in hand | `semble` (MCP) |
| Match depends on syntax shape, or a rewrite | `ast-grep -p '<pat>' -l <lang>` (`-U` applies) |
| Literal/regex text, path lookup, repeated in one repo | fff MCP: `grep`, `find_files`, `multi_grep` |
| One-off search outside a git repo | `rg` / `fd` (never `find`, never `grep` CLI) |

- LSP answers from the compiler's own resolution, so prefer it wherever a server is
  enabled (Kotlin, Rust, TypeScript). LSP needs a file and a position, so it answers
  "who calls THIS", never "what matters in this repo".
- semble is the cold-start lane: it matches meaning when no identifier is known yet.
  Once a symbol name is in hand, LSP is the precise answer; fff for literal text and
  ast-grep for shape-dependent matches or rewrites.
- semble chunks are function-scoped with no caller or import context. Read the
  full file (or ±80 lines) before reasoning about a change. Locators, not context.
- fff holds a warm index per repo — pays off from the second search.
  `multi_grep` for N identifiers in one call.
- `sd` over `sed` for find & replace: global by default, no BSD `-i ''` quirk.
  Literal `$` is `$$`. Fall back to `sed`/`awk` only for line-addressed ops.

## Shell for the Bash tool

`CLAUDE_CODE_SHELL=/opt/homebrew/bin/bash` in `~/.claude/settings.json` pins Bash
tool commands to Homebrew bash 5.3.

Without it, Claude Code auto-detects: `$SHELL` when it names bash or zsh, otherwise
the first working zsh, then bash, on PATH. Here `$SHELL=/bin/zsh`, so commands ran in
zsh, where a bare `=word` is equals-expansion — `echo ===` fails with
`(eval):1: == not found` and exits 1, easy to miss behind the real output of a
compound command. Quote the separator (`echo '==='`) wherever zsh may still run it.

Only bash and zsh are accepted; fish is not, and a path that is neither falls back to
auto-detection without a warning. `defaultShell` in settings.json is a different
setting — it chooses bash or PowerShell for `!`-prefix commands typed in the input box.

Apple's `/bin/bash` is 3.2 and is the fallback on a machine without the Homebrew
formula: no `${var^^}`, no associative arrays, no `mapfile`, no `globstar`. Prefer
`python3` over bash 4+ syntax in anything that has to run there.

## Sandbox and secrets

Inside Claude Code's sandbox the 1Password desktop app is unreachable, so `fnox`
resolves nothing. `op` binds its daemon socket under `~/.config/op`, which is not
writable there, and the app's per-client socket in the 1Password group container
has a random per-client name with no stable path to allowlist. Anything needing a
credential must therefore run outside the sandbox — as an MCP server Claude Code
starts itself — or not need one at all.

`$TMPDIR` is the tell: the sandbox points it at `/tmp/claude-<uid>`, while an
unsandboxed shell leaves it at `/var/folders/.../T/`.

## Vy train data MCP servers

`journey` and `ruteplan` overlap. For CargoNet freight — a cargo journey, a terminal
departure board, a PLC, a top level train ID — prefer `journey`: it is the operational
source CargoNet itself runs on, and it renders markdown rather than raw Elasticsearch
documents. Reach for `ruteplan` for what `journey` does not cover: the SIRI/Entur
pipeline (`trace_siri_pipeline`), train composition, per-stop event streams, raw
BaneNOR/Trafikverket messages, and passenger traffic.

They share vocabulary without sharing meaning, so do not carry ids or conclusions
between them:

- A `journey` "journey" is a CargoNet cargo run (UUID). Ruteplan's is a SIRI/Entur
  `DatedServiceJourney`. Unrelated entities.
- `journey` takes a PLC (`NO201`); ruteplan uses stopIds (`OSL`). Resolve a PLC with
  `journey_find_terminal`, not `search_oppoint`.
- `journey`'s `trainNumber` is the TOP LEVEL number. Ruteplan's "operational train
  number" is the OTN, one level below it.
- Both report delays, from different pipeline stages, and can legitimately disagree.
  Say which one an answer came from.

`nominalDate` does mean the same thing in both: the date the train departs its origin.

## GitHub

Use the `github` MCP tools. Never the `gh` CLI — it is denied in
`permissions.deny`, and it has no credentials in any case: `~/.config/gh/hosts.yml`
is empty and the fnox wrapper that fed it `GH_TOKEN` has been removed. The token
now exists only inside `github-mcp-server`, which Claude Code starts outside the
sandbox as `fnox exec -- github-mcp-server stdio`.

## Task board

Work that outlives one session goes on the tsk board (`tsk`, installed by mise
as `github:smarzban/tsk`), shared by me and every Claude session across all repos.
Inside a git repo the board scopes to that repo's project. The `tsk-cli` skill
has the commands and the exit contract; a SessionStart hook lists the repo's
live tasks.

- Add a task when work is deferred, split off, or found along the way, not for
  steps you will finish this session. Use steps (`tsk steps`) only when I want
  the order of work tracked on a task.
- Picking up a task: `tsk status T<n> start`, tick its steps as they land, then
  `review` with one line on what to look at. Only I set `done`.
- Won't do: when we decide against something, record the decision instead of
  dropping it. Archive the task (`tsk archive`) with notes starting
  `Won't do: <reason>`, so a later session doesn't propose it again.
- Only the main agent writes to the board. Subagents report back.
- In a git worktree, pass `-p <main checkout path>` to `tsk add` and `tsk list`:
  tsk otherwise treats each worktree as its own project. The SessionStart hook
  names the path.
- In herdr, `prefix+t` opens the board and `prefix+ctrl+t` quick capture.

## Commit messages

Indent the body with 2 spaces (from line 2 and below).

## Code comments

Do not add comments of these kinds — they are self-shaming, not useful to whoever
reads the code later:

- **Unnecessarily verbose** comments that restate what the code already says.
- Comments that **mention mistakes made along the way** that are just part of the
  current work-in-progress (e.g. "removed X because it broke Y earlier", "no longer
  using Z"). The final code stands on its own; the detour is not part of it.

Comment the non-obvious *why* when it genuinely helps a future reader; skip the rest.
