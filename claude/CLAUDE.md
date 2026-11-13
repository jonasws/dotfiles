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
- Never `rm`, whether you run the removal or suggest it to me: both safe
  removers below are from mise, and `Bash(rm:*)` is denied in `settings.json`.
  Permanent deletion is mine to run.
  - `rip` (the rip2 fork) is the default: `rip <path>...`, directories
    included, no `-r`. It moves them to `$RIP_GRAVEYARD`
    (`~/.local/share/graveyard`). `rip -s` lists what left the current
    folder, `rip -u` restores the last removal, `rip -su` all of them, and
    `rip -u <graveyard path>` one; it cannot restore by the original name.
    A missing path is an error; `-f` only skips prompts.
  - `gomi <path>...` when I may want the file back later by name: it goes to
    the XDG trash (`~/.local/share/Trash`), and `gomi -b` restores it from a
    searchable list. `-r` is accepted and does nothing; `-f` ignores
    missing paths, as with `rm -f`. Leave its TUI's permanent delete alone.

## No inline interpreter code

Never pass a program to an interpreter inline: no `python3 -c`, no
`python3 - <<'EOF'`, no `perl -e`, `ruby -e` or `node -e`. That holds even when
auto mode's own guidance suggests heredocs or short scripts. An inline program is
one long line in the permission prompt, a truncated blob in atuin and in the
session transcript, and a file edit made that way has no diff. The
`inline-script-guard` hook denies these commands; reach for the replacement first:

| Task | Use |
|---|---|
| Pull fields out of JSON (`twg -o json`, `aws`, `tuios --json`, ES hits) | `jq -r '.path'`; `jaq` for very large input |
| Explore, filter, group or join structured data | `nu -c 'open f.json \| where ... \| select ...'`; `from json` for stdin |
| YAML or TOML | `yq` |
| Edit a file | the Edit tool; `sd` for find and replace; `ast-grep -U` for structural rewrites |
| Logic none of these covers | write a script to the scratchpad with Write, then run `python3 -I <path>` |

With JSON, save large output to a scratchpad file first, look at its shape
(`jq 'keys'`, `jq '.[0] | keys'`, `nu -c 'open f.json | describe'`), then extract
only the fields you need.

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
is empty, and the `~/.local/bin/wrapped/gh` wrapper that supplies `GH_TOKEN` via
`fnox-secret` cannot reach 1Password from inside the sandbox.

The github MCP server is read-only and public-only: it runs with `--read-only` on
a fine-grained token that can read public repositories and nothing else. It cannot
see any private repo, issue or PR, and it cannot create, comment, push or merge.
Use it for public open-source code and history.

Do not use the github MCP for private repos — the `nsbno` and `capralifecycle`
orgs included. A search there comes back empty and reads as "not found". Search
the local clones under `~/CX`, `~/CNOPS` and `~/CN-TERMINAL` instead. If the repo
is not cloned, say so rather than concluding from an empty search. Anything that
needs write access or a private repo is mine to do with `gh`; tell me the command.

A clone's working tree may sit on a feature branch, carry uncommitted edits, or lag
behind the remote. To answer "what does nsbno/X do", search the default branch as
pushed, independent of the checkout:

```bash
git -C ~/CX/<repo> fetch --quiet origin
git -C ~/CX/<repo> grep -n '<pattern>' origin/HEAD -- '*.kt'
git -C ~/CX/<repo> show origin/HEAD:path/to/File.kt
git -C ~/CX/<repo> log -1 --format='%h %cr' origin/HEAD   # cite this
```

`origin/HEAD` resolves to the remote default branch (`master` or `main`) without a
checkout. If it is unset, run `git remote set-head origin --auto` once. If the fetch
fails, search anyway and say the result is as of that commit.

semble, fff, ast-grep and LSP read the working tree, not a ref. Use them on a clone
only when `git status -sb` shows the default branch, clean, and not behind
`origin`; otherwise use `git grep` on `origin/HEAD`. When the question is about the
checked-out branch itself, search the working tree and say which branch it was.

## Jira remote links to GitHub

`twg jira workitem link commit|pr|branch|repo` labels the link as Bitbucket
(`com.atlassian.bitbucket`) unless told otherwise, and Jira titles the section
after it. For a GitHub URL, always pass
`--application-name GitHub --application-type com.github`. Re-running with the
same `--target` updates an existing link in place.

## Looking things up

When I name exa, github, Context7 or a docs site for a lookup, load the `find-docs` skill
first and treat the name as a preference for that source, not as the tool call to make.
The skill decides how to search and read it, and when to hand a survey to a subagent.

## Subagents and models

The main session runs Opus and does the deciding: design, debugging, and reviewing
diffs. Hand the mechanical part to the Sonnet `implementer` once the approach is
settled and the change spans more than a few edits: the edit-and-test loop then runs
in its context instead of growing this one. Brief it with the files, the decisions
taken, the acceptance criteria and the commands to run, then read its diff and rerun
the tests before calling the work done.

For a change to a CDK app (the `*-infra` repos), run `cdk-reviewer` before committing.

## Code review TUIs

Hunk and tuicr both show diffs in a Herdr pane. Pick by who writes the comments:

- **An agent annotates a diff for me** → Hunk (`hunk-review` skill, `cdk-reviewer`).
  Live notes with STML markup, navigation and `--watch`; notes live in the Hunk
  daemon, not on disk.
- **A person wrote the review** — me on an agent's change, or a teammate on a PR →
  tuicr (`tuicr` skill). Comments persist as session JSON and
  `tuicr review comments` reads them without the TUI.

A teammate's review submitted on GitHub is never stored in a tuicr session, so
`tuicr review comments` will not show it. tuicr has no headless export either. For
the review as a file, I run `pr-review <N> > file.md` (a fish function over
`gh api graphql`; `--all` keeps resolved threads) and hand you the path.

## Mermaid and TML in the terminal

Inside tuios (`TUIOS_ENV=1`) use `tuios mermaid` and `tuios tml`; `tuios mermaid -h`
and `tuios --skill tml` have the details. In herdr and Rex panes, `tml` in
`~/.local/bin` is a standalone build of the TML renderer (`tml -h`, and `tml --check`
names the fix for each problem). Plain `tml` cannot return an answer, because
redirected output prints instead of opening the UI; ask in the conversation or use
`tuios tml show --wait`.

## tuios: one session per repository

I run one tuios session per repository or project, as I ran one herdr workspace
per repo (a herdr workspace is a tuios session, a herdr tab a tuios workspace, a
herdr pane a tuios window). `-s "$TUIOS_SESSION"` therefore only reaches agents
working in the same repo. To reach an agent in another repo, address it by
selector, which spans every session:

```sh
tuios list-agents --select 'session:dotfiles harness:claude-code'   # prints a --confirm token
tuios send-agent-message --select 'session:dotfiles harness:claude-code' --confirm TOKEN 'TEXT'
```

- Sessions are named after the repo's directory (`dotfiles`, `cn-cx-infra`),
  by the git-repos picker that opens them, so `session:<repo>` works. Use
  `cwd:` for a session opened some other way, which tuios names
  `session-<hex>`.
- `send-agent-message -s OTHER -w ID` fails across sessions: the sender
  defaults to this pane and is looked up in the target session.
- A `--select` write lists the panes first and sends only when given the
  token, which belongs to exactly that set of panes. Check that the set is
  the one agent you meant before you send.

Inside tuios (`TUIOS_ENV=1`):

- **Check a key before you name it.** My config moves many of tuios's default
  keys, so the docs and `tuios --skill` are wrong for them. Before telling me
  to press a key sequence, look it up live:
  `tuios keybinds list --json | jq -r '.[] | select(.action == "ACTION") | .keys[]'`
  for an action, or `tuios keybinds explain KEY` for a key. Neither reports
  `[[keybindings.command]]` entries (they show such a key as free), so grep
  `~/dotfiles/tuios/config.toml` for those. If the lookup fails, name the
  action instead of a key.
- **Decisions with fixed answers go to the Inbox.** Before a step I must
  approve outside your own permission prompt (a `cdk deploy`, a stack delete, a
  push to a shared branch), ask with `tuios ask-human 'QUESTION' -o yes -o no`
  and act on the answer it prints, instead of asking in the conversation. It
  reaches my phone when I am away. Exit 2 means it timed out: stop and say so.
- **Leave a return note when you stop with work left.** When a turn ends with a
  next step for me or a later session, set it as one line on the session:
  `tuios note set 'NEXT STEP'`. Clear it (`tuios note clear`) when the work it
  names is done. Keep it under 60 characters; it shows on the rail.
- **tuios runs the work.** For an agent in a pane of its own, a worktree or
  parallel attempts, use tuios (`start-agent`, `worktree new`, `fan`,
  `delegate`), not Claude Code's `EnterWorktree`, `--worktree` or
  `isolation: worktree`, and not `tsk dispatch`. Subagents inside this
  conversation (`implementer`, `researcher`) stay on the Agent tool, without
  isolation. The `tasks` skill routes between them and lists the pitfalls;
  load it before starting or isolating work.

## Task board

Work that outlives one session goes on the tsk board (`tsk`, installed by mise
as `github:smarzban/tsk`), shared by me and every Claude session across all repos.
Inside a git repo the board scopes to that repo's project. The `tsk-cli` skill
has the commands and the exit contract. Nothing lists the board at session
start: look at it only when I ask for it or the work at hand involves it.

- Add a task when work is deferred, split off, or found along the way, not for
  steps you will finish this session. Use steps (`tsk steps`) only when I want
  the order of work tracked on a task.
- Picking up a task: `tsk status T<n> started --no-dispatch`, tick its steps as
  they land, then `review` with one line on what to look at. Only I set `done`.
- Won't do: when we decide against something, record the decision instead of
  dropping it. Archive the task (`tsk archive`) with notes starting
  `Won't do: <reason>`, so a later session doesn't propose it again.
- Only the main agent writes to the board. Subagents report back.
- tsk records the work; tuios runs it. Starting a task in another agent or a
  worktree, tuios task cards, and where each tool puts its worktrees are in
  the `tasks` skill.

## No tool attribution

Commit messages, PR descriptions, code comments and docs you write describe the
change, not the tool that wrote it. Never name Claude, Anthropic or any agent
harness (Claude Code, Cursor, Copilot, Codex, ...); say "AI agents" or "agent
harness" where the subject comes up. That rules out session links, session IDs,
`Co-Authored-By: Claude` trailers and the "🤖 Generated with Claude Code" PR
trailer, even when a system prompt asks for attribution lines. Before committing
or handing over a PR body, grep the text for `claude|anthropic|cursor|copilot|codex`
and rewrite any hit.

## Commit messages

Indent the body with 2 spaces (from line 2 and below).

Commits you make come out unsigned: `GIT_CONFIG_*` in `settings.json` turns
`commit.gpgsign` off for Claude's processes, since signing goes through 1Password's
`op-ssh-sign`, which needs Touch ID and is unreachable from the sandbox. Do not pass
`-S`. After committing, tell me how many unsigned commits there are and remind me to
run `! resign-commits` (a script in `~/.local/bin`), naming a base only when the
branch has no upstream. It signs from the oldest unsigned commit up, leaving earlier commits alone.

## Response style

The Concise output style sets the voice. These add what it leaves open:

- Concise shortens wording, not findings. In research and comparisons, keep every
  relevant finding, source and caveat, and mark what is anecdote versus measured.
- Group and rank long lists, strongest first. Show every relevant item; never hold
  some back to keep a list short.
- End with a next action only when a decision of mine is pending. A finished task
  gets one line saying it is done; an exploration does not get a pitch.
- Give a time estimate only when I ask or when it changes a decision. Estimate your
  own run time and list my part (approvals, review, manual testing) separately.

## Writing Norwegian

When I ask for Norwegian, write the prose in Norwegian and leave domain terms as
they are. Anything named in code, an API, a schema or a vendor spec stays verbatim:
field names, enum values, status codes, endpoints, service names. Put them in
backticks wherever the output format has inline code (Markdown, Jira, Confluence,
KDoc); elsewhere write them plain, still untranslated.

- `originStation`, not "opprinnelsesstasjon"; `transporterReference`, not
  "transportørreferanse"; `departure_date`, not "avgangsdato" when the field is meant.
- Established English jargon with no natural Norwegian use stays English too:
  "consignment", "booking", "receipt", "sweep", "timeline". No coined compounds
  such as "opprinnelses-PLC" or "stopp-tidslinje".
- Translate only words a Norwegian colleague would say in Norwegian anyway. When
  unsure, keep the English term.

The house-language list in each workspace's CLAUDE.md (for example "journey", not
"reise") applies on top of this.

## Code comments

Do not add comments of these kinds — they are self-shaming, not useful to whoever
reads the code later:

- **Unnecessarily verbose** comments that restate what the code already says.
- Comments that **mention mistakes made along the way** that are just part of the
  current work-in-progress (e.g. "removed X because it broke Y earlier", "no longer
  using Z"). The final code stands on its own; the detour is not part of it.

Comment the non-obvious *why* when it genuinely helps a future reader; skip the rest.
