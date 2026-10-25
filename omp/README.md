# oh-my-pi (omp)

[oh-my-pi](https://github.com/can1357/oh-my-pi) ([omp.sh](https://omp.sh)) is
Stencil Labs' "batteries included" fork of pi: LSP and DAP, AST edits, a native
bash with in-process coreutils, subagents with worktree isolation, agent memory,
web search, MCP, and discovery of other agents' config. This directory sets it
up to use those batteries, run well inside herdr, and stay contained the way
Claude Code is here (`claude/settings.json`), with an Anthropic API key and no
subscription login.

Pinned against omp 18.12.6 and nono 0.80.0 (October 2026). Upstream doc paths
below are relative to the omp repository.

## Files

| Path | Deployed to | Role |
|---|---|---|
| `omp/config.yml` | `~/.omp/agent/config.yml` | Preferences: models, discovery, batteries, UI |
| `omp/policy.yml` | not deployed | Approval and privacy policy, loaded as an overlay by the launcher |
| `omp/AGENTS.md` | `~/.omp/agent/AGENTS.md` | User-level instructions |
| `omp/mcp.json` | `~/.omp/agent/mcp.json` | The github MCP server |
| `omp/lsp.json` | `~/.omp/agent/lsp.json` | kotlin-lsp through `~/.local/bin/intellij-server`, as in `claude/settings.json` |
| `fnox/wrapped/omp` | `~/.local/bin/wrapped/omp` | Launcher: resolves credentials, enters nono |
| `nono/profiles/omp.json` | `~/.config/nono/profiles/omp.json` | The sandbox |

The `omp` dotfile group links each file (`symlink-each`), so sessions,
`agent.db`, memories, the natives cache and herdr's extension stay local in
`~/.omp/agent`. omp is installed by mise as `github:can1357/oh-my-pi` (the
release binary; `mise-global/config.toml` says why not npm), and `update:omp`
in `mise.toml` refreshes herdr's omp extension and omp's plugins daily.

## Setup

1. Create `Employee/Anthropic API Key` (field `credential`) in 1Password. Use
   a key in a workspace with a monthly spend limit: the key is readable by the
   agent's own commands (see [Credentials](#credentials)).
2. `mise run sync-secrets` from `~`, to give the new `ANTHROPIC_API_KEY` entry
   in `fnox/config.toml` its sync blob, so it shares the one Touch ID.
3. `mise install` and `mise -C ~/dotfiles dot apply`.
4. `herdr integration install omp`. It writes
   `~/.omp/agent/extensions/herdr-omp-agent-state.ts` and refuses when pi and
   omp would share an extension directory; pi uses `~/.pi/agent`.
5. Check the sandbox before the first session, from a repo:
   `nono run --profile omp --allow-cwd --dry-run -v -- true` lists every grant.
   `nono why --profile omp --path ~/.ssh --op read` explains a single decision.
6. Run `omp`. On a denial nono prints a diagnostic footer when omp exits; add
   what is missing to `nono/profiles/omp.json`, never by hand-loosening a
   session.

Settings changes go into `omp/config.yml`, not `/settings`: the sandbox denies
writes to `~/dotfiles/omp`, so omp cannot save from inside a session, and
interactive sessions reload the file live.

## Batteries

| Battery | State | Why |
|---|---|---|
| Native tools: `read` summaries, hashline `edit`, `grep`/`glob`, `ast_grep`/`ast_edit`, embedded bash | on (default) | The point of omp. `bashInterceptor` is turned on so `cat`/`rg`/`sed -i` in bash get routed to them, the omp form of the search-tool table in `claude/CLAUDE.md` |
| `lsp` | on, also for subagents (`task.enableLsp`) | Compiler-resolved navigation for Kotlin, TypeScript, Rust |
| `task` subagents | on, `task.isolation.enabled`, 3 concurrent, depth 2 | Limits as `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`/`_SPAWN_DEPTH`; isolation copies go to `~/.omp/wt`. Subagents run in-process, inside the same sandbox |
| `eval` (Python, JavaScript) | on, every call asks | It can spawn processes that `bash.patterns` never sees |
| `web_search` + URL `read` | on, `web/exa` then `web/hosted` | Exa key from fnox; hosted is Claude's server-side search on the same API key. The explicit chain keeps omp's keyless scrapers out |
| Memory (`retain`/`recall`/`learn`) | on, `memory.backend: local` | Project-scoped, local SQLite, summarised by haiku |
| Session recap, titles, `omp commit` | on | Small haiku calls |
| Advisor (second model reviewing each turn) | configured, off | `/advisor on` uses Sonnet; on by default it roughly doubles spend |
| `browser` (Puppeteer) | on (default) | Untested under nono, see gaps |
| MCP | github server only | `omp/mcp.json`. Project `.mcp.json` files are off (`mcp.enableProjectConfig`): omp starts them without the trust prompt Claude Code shows |
| Skills | `~/.agents/skills`, `~/.claude/skills`, repo `.claude/skills` | Minus three that drive Claude Code itself (`config.yml`) |
| Context files | `~/.omp/agent/AGENTS.md` + each repo's `AGENTS.md`/`CLAUDE.md` | See [Discovery](#discovery) |
| `github` tool | off | It drives `gh`, which is denied and has no credentials |
| `computer` (desktop control) | off | Screenshots and input outside any window |
| `security_scan`, `generate_image`, `tts`, autolearn | off (default) | Other providers, or experimental |
| Telemetry: OTLP export, `dev.autoqa` reports to qa.omp.sh | off, pinned in `policy.yml` and the profile env | Org code must not leave in tool-failure reports |
| `/collab`, `/share`, `omp stream` | available, never automatic | They upload (encrypted) session content to my.omp.sh. `collab.autoStart` is pinned off; only a person running the command publishes |
| Self-update | off | mise owns the binary |

## Discovery

omp reads other agents' files in their native shape
([docs/context-files.md](https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md)).
Foreign **user-level** sources are opt-in through `enabledProviders`, and stay
out (pinned empty in `policy.yml`, so a repo cannot opt itself in):

- `~/.claude/CLAUDE.md` is written for Claude Code's tool names and sandbox.
  `omp/AGENTS.md` adapts what carries over (search tools, GitHub and private
  repo rules, commit rules, herdr rules) and, as the native user file, shadows
  every other user-level context file anyway.
- `~/.claude.json` and `~/.claude/settings.json` would bring Claude's MCP
  servers and settings. Those servers start through fnox wrappers that cannot
  reach 1Password from inside nono.

Project-level sources stay on, so omp works in the org repos as they are: a
repo's `CLAUDE.md` and `AGENTS.md`, `.claude/skills`, `.claude/commands`,
`.github/copilot-instructions.md`, cursor and cline rules. Both `CLAUDE.md` and
`AGENTS.md` load where a repo has both, which upstream does on purpose
([#2612](https://github.com/can1357/oh-my-pi/issues/2612)); a per-file switch
is open as [#10049](https://github.com/can1357/oh-my-pi/issues/10049). Until
then `disabledExtensions: [context-file:project:CLAUDE.md]` drops one file and
`disabledProviders: [claude-md]` the whole source, if the duplication costs too
much context. omp also merges a repo's `.claude/settings.json` and
`.omp/config.yml` into its settings as the project layer, which is why the
policy lives in an overlay above them.

## Containment

omp has no OS sandbox. Its approval modes decide when to ask, and its own docs
say a `bash.patterns` rule "is an approval policy, not containment"
([docs/approval-mode.md](https://github.com/can1357/oh-my-pi/blob/main/docs/approval-mode.md)).
Claude Code sandboxes only its Bash tool; here the whole omp process runs in
[nono](https://github.com/always-further/nono) (Seatbelt on macOS), so the
bash tool, eval kernels, LSP and MCP servers, the browser and in-process
subagents all inherit one sandbox.

| Layer | Enforced by | Covers |
|---|---|---|
| Filesystem, sockets, env | nono (kernel) | Everything omp and its children do |
| Credentials | launcher + nono | Only four low-stakes secrets enter; no 1Password, `~/.ssh`, `~/.aws`, fnox keys |
| Command approval | omp `policy.yml` | Commands as typed in the bash tool; eval asks every time |
| Instructions | `omp/AGENTS.md` | Conventions the model is asked to follow |

### What nono enforces (`nono/profiles/omp.json`)

Mapped from `claude/settings.json` `sandbox`:

- **Base:** extends nono's `default` profile, which denies `~/.ssh`, `~/.aws`,
  `~/.docker`, `~/.gnupg`, `~/.config/op`, keychains, browser data, shell
  configs and history, and reads only system paths plus `~/.local/bin`. Groups
  add read access to the toolchains (`~/.bun`, mise, `~/.npm`, cargo/rustup,
  `~/.m2/repository`, git config). Nothing else in `~` is readable, the nono
  form of `denyRead: ["~/"]` with an allow list.
- **Read:** Claude's `allowRead` list, plus `~/.claude/skills`. Docker's
  `config.json` and `contexts` are re-opened through `bypass_protection`,
  since the default profile denies all of `~/.docker`.
- **Read-write:** Claude's `allowWrite` list plus `~/.omp` (omp's state) and
  the working directory. nono refuses `~` itself as a working directory, so
  the launcher moves to `$TMPDIR` first, as omp would.
- **Write-denied inside those:** `~/dotfiles/{claude,fish,fnox,herdr}` as in
  Claude's `denyWrite`, plus `nono` and `omp` and the linked files in
  `~/.omp/agent`, so the agent cannot rewrite its own containment, launcher or
  policy. Also `mise-global` (its `_.path` is what puts the launcher first on
  every shell's PATH, and its `[env]` and hooks run in every shell), `git`
  (`~/.config/git/config`: aliases, `core.hooksPath`) and `bin`
  (`resign-commits`, which I run by hand). Seatbelt evaluates the last matching rule
  and nono emits raw rules after its grants, which is what lets
  `unsafe_macos_seatbelt_rules` carve a write deny out of a read-write tree.
  nono honours raw rules only in user-authored profiles, and they cannot
  expand `$HOME`, hence the literal `/Users/jonasws`.
- **Read-denied anywhere:** `*.env`, `*.env.*` and `*-env` file contents
  (`permissions.deny` `Read(//**/.env)` etc.), as runtime regexes so files
  created later are covered, plus `~/dotfiles/fnox/age*.txt` and
  `~/.m2/settings-security*.xml*`.
- **Write-denied anywhere:** files that another program executes later,
  outside any sandbox: `.git/hooks`, `.git/config` (`core.fsmonitor`,
  `core.pager`, aliases), `.claude/settings*.json`, `.claude/{hooks,commands,
  agents}`, `.mcp.json`, `.envrc`, `.vscode/`, `.idea/`. A hook planted in a
  repo would otherwise run the next time I commit, and a `.claude/settings`
  hook the next time Claude Code opens the repo, unsandboxed in `~/dotfiles`.
  This follows the list Anthropic's sandbox-runtime protects.
- **Unix sockets:** added by the launcher, only when present: the 1Password
  SSH agent, `herdr.sock` (inside herdr), colima's `docker.sock`. Local port
  binding and outbound network are open, as in Claude's settings, which set no
  domain allow list.
- **Environment:** `GIT_CONFIG_*` turns signing off for every git the agent
  runs, as in `claude/settings.json` `env`; `OTEL_SDK_DISABLED` and
  `PI_AUTO_QA=0` back the telemetry settings; `OMP_SANDBOX=nono` marks the
  sandbox for the launcher; full-access tokens (`GH_TOKEN`, `GITHUB_TOKEN`,
  the maven ones, AWS keys, `OP_SESSION_*`) are stripped if a shell exports
  one by hand.
- **Processes:** `allow_same_sandbox` signals and process info, so omp can stop
  the jobs it started; `ipc_mode: full` for Python multiprocessing in eval.

### What omp's policy enforces (`omp/policy.yml`)

`tools.approvalMode: yolo` with targeted rules, omp's nearest equivalent to
Claude's `defaultMode: auto`. Loaded through `PI_CONFIG_FILES` as an overlay, it
outranks `~/.omp/agent/config.yml` and every repo's project settings
([docs/settings.md](https://github.com/can1357/oh-my-pi/blob/main/docs/settings.md#precedence)).

- **Deny** (`permissions.deny`): `gh`, `fnox get/export`, `op read`, `op item
  get`, `op inject`, `op document get`, `twg`; any command naming `herdr.sock`,
  `docker.sock` or the SSH agent socket (autoMode `hard_deny` on raw clients).
- **Ask** (`permissions.ask`): force push, push `--delete`/`:ref`, `reset
  --hard`, `clean -f`, rebase; docker with `--privileged`, host namespaces,
  capabilities, devices or any bind mount.
- **herdr:** reads, tabs and splits run freely. `pane run`, `send-text`,
  `send-keys`, `agent prompt`, `agent send-keys`, closing or moving panes and
  tabs, `server`, `plugin` and `integration` ask. `agent start` runs without
  asking only for `--kind omp`.
- **eval asks** on every call.
- **Pinned:** project MCP off, `enabledProviders: []`, direnv off, github and
  computer tools off, telemetry and autoqa off, `collab.autoStart: off`,
  `secrets.enabled` on.

### Threat model: herdr

A herdr pane is a fresh login shell started by the herdr server, outside every
sandbox, with my full rights. Whoever can write to `herdr.sock` can run
anything there: `herdr pane run`, `send-text`/`send-keys` into my shells or
another agent, `agent start` of an uncontained agent. Claude's setup grants the
socket and relies on its auto-mode classifier to tell its own viewer panes from
mine.

- **Spawned agents stay contained.** `herdr agent start --kind omp` types `omp`
  into the pane's shell (`src/app/agents.rs`), which resolves it through PATH
  to the launcher, as does herdr's own `omp --resume=<id>` after a server
  restart. It would only escape if the agent could put something ahead of
  `~/.local/bin/wrapped` on that shell's PATH, and the fish, mise and herdr
  config that decide PATH are all write-denied.
- **Arbitrary pane commands are only soft-gated.** The socket is granted to the
  whole sandbox, so the `ask` rules above are all that stands between the agent
  and an unsandboxed command. They match the command line as typed: a script
  file, `xargs`, or eval's `subprocess` get past them. eval asks every time to
  narrow that. For untrusted work, start omp with `OMP_HERDR_SOCKET=0` (no
  socket: no herdr CLI and no sidebar state), or outside herdr.
- **The real fix** is nono's command mediation
  ([tool-sandbox](https://github.com/always-further/nono/blob/main/docs/cli/features/tool-sandbox.mdx)):
  grant `herdr.sock` only to a mediated `herdr` command with an argv
  `invocation_policy`, not to the session. It is not used yet because
  mediation also limits the session to executables on PATH, which breaks JVM
  helpers such as `jspawnhelper` and needs testing on the Mac first.

### Credentials

The launcher resolves these with `fnox-secret` before entering the sandbox
(1Password is unreachable inside, `claude/CLAUDE.md` "Sandbox and secrets") and
passes them to omp as environment variables:

| Variable | Source | Use |
|---|---|---|
| `ANTHROPIC_API_KEY` | `ANTHROPIC_API_KEY` | Model provider |
| `EXA_API_KEY` | `EXA_API_KEY` | `web_search` via Exa |
| `CONTEXT7_API_KEY` | `CONTEXT7_API_KEY` | context7 skill |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | `MISE_GITHUB_TOKEN` (public read only) | github MCP server, which omp starts inside the sandbox; `fnox/wrapped/github-mcp-server` uses a token already set |

Every command omp runs inherits them, so a prompt-injected agent can read and
send them anywhere. `secrets.enabled` replaces their values with placeholders
in what goes to Anthropic, but restores them in tool arguments before a
command runs, so it protects transcripts, not the keys. The full-access GitHub
token, the maven credentials and Jira never enter.

nono can keep a key out entirely: a `custom_credentials` route with a `cmd://`
capture runs `fnox-secret ANTHROPIC_API_KEY` in its supervisor and injects the
header in a local reverse proxy, leaving only a phantom token and
`ANTHROPIC_BASE_URL` in the sandbox
([credential-injection](https://github.com/always-further/nono/blob/main/docs/cli/features/credential-injection.mdx)).
Not used because any proxy route puts nono in proxy-only mode, where on macOS
the sandbox may only connect to the local proxy: git over ssh and other raw TCP
stop working. omp treats a rerouted base URL as non-official and drops
Anthropic-only features such as server-side compaction too.

## Gaps and risks

- **Untested on macOS.** Built on Linux, where Seatbelt does not exist. Checked:
  `nono profile validate` and `--dry-run` with nono 0.80.0, the profile against
  nono's schema, every key in `config.yml` and `policy.yml` against omp 18.12.6
  (`omp config list --json` shows each with the intended effective value), the
  overlay winning over a hostile `.omp/config.yml` and `.claude/settings.json`
  in the working directory, a model request reaching Anthropic with the
  configured roles, the launcher's
  argument and environment handling with stub `mise`/`nono`/`fnox-secret`, and
  shellcheck. Not checked: any Seatbelt rule at runtime, the raw regex rules,
  omp's TUI, natives, clipboard and browser under the sandbox, herdr's
  extension reporting through the socket, `bash.patterns` matching live.
- **Unpinned keys stay repo-settable.** Objects deep-merge, so a repo can add
  `tools.approval.<tool>: allow` for a tool `policy.yml` does not name. It
  cannot override a `bash.patterns` deny or prompt, which omp resolves before
  user policy.
- **A raw-rule typo fails open on that path,** not closed: verify with
  `nono why` that `~/dotfiles/omp/policy.yml` and a repo's `.git/hooks` are
  not writable.
- **`.git/config` write deny breaks** `git clone`/`git init` inside the
  sandbox, `git push -u` and `git remote set-head`. Run those outside.
- **omp reads the working directory's `.env` at startup** for provider keys
  (docs/environment-variables.md); under the read deny that read fails.
  Expected to be ignored, unverified.
- **Other live-linked dotfiles stay writable:** nvim and wezterm Lua,
  television channels, lazygit custom commands and the like run code the next
  time I open the tool, as with Claude Code, which runs unsandboxed in
  `~/dotfiles`.
- **Docker reaches past nono:** a container sees `~/CX` and `~/CNOPS` through
  colima's writable mounts, `.env` files and `.git/hooks` included. The docker
  ask rules match flags as typed only.
- **Writes the user later executes:** the agent can still edit `mise.toml`
  (`[hooks]` run on `cd`), Makefiles and build scripts in any writable repo.
  Inherent to a coding agent; review diffs.
- **Worktrees of this repo** under `~/.herdr/worktrees` hold writable copies of
  `claude/`, `fnox/`, `nono/` and `omp/`; changes there land only through a
  commit I merge.
- **Settings cannot be saved from a session** (`/settings`, `/model` roles,
  `omp config set`): edit `omp/config.yml`.
- **`shellPath`** is Homebrew bash; omp refuses to start where that path is
  missing.
- **ssh:** `~/.ssh` is unreadable, so ssh inside the sandbox has no config or
  `known_hosts`. Git over ssh may need `GIT_SSH_COMMAND` or HTTPS remotes;
  unverified, as in Claude's sandbox, which denies `~/.ssh` the same way.
- **omp daemons:** a broker started by an omp running outside nono could run
  `name`d bash services for a sandboxed one. Only ever start omp through the
  launcher.

## Sources

- omp: [README](https://github.com/can1357/oh-my-pi/blob/main/README.md),
  [settings](https://github.com/can1357/oh-my-pi/blob/main/docs/settings.md),
  [approval mode](https://github.com/can1357/oh-my-pi/blob/main/docs/approval-mode.md),
  [bash tool](https://github.com/can1357/oh-my-pi/blob/main/docs/tools/bash.md),
  [context files](https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md),
  [MCP](https://github.com/can1357/oh-my-pi/blob/main/docs/mcp-config.md),
  [LSP](https://github.com/can1357/oh-my-pi/blob/main/docs/lsp-config.md),
  [secrets](https://github.com/can1357/oh-my-pi/blob/main/docs/secrets.md),
  [environment variables](https://github.com/can1357/oh-my-pi/blob/main/docs/environment-variables.md),
  [web search](https://github.com/can1357/oh-my-pi/blob/main/docs/tools/web_search.md),
  `omp config list --json` for every key and default.
- nono: [profile authoring guide](https://github.com/always-further/nono/blob/main/crates/nono-cli/data/profile-authoring-guide.md),
  [networking](https://github.com/always-further/nono/blob/main/docs/cli/features/networking.mdx),
  [execution modes](https://github.com/always-further/nono/blob/main/docs/cli/features/execution-modes.mdx),
  built-in groups in `crates/nono-cli/data/policy.json`.
- herdr: [integrations](https://herdr.dev/docs/integrations/),
  [agent automation](https://herdr.dev/docs/agent-automation/),
  `src/app/agents.rs` (agent start types the kind's executable into the pane's
  shell), `src/integration/assets/omp/herdr-agent-state.ts`.
