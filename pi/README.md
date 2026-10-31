# pi

[pi](https://github.com/earendil-works/pi) as the brain, [herdr](https://herdr.dev)
as the room. pi does the work; herdr holds the panes it and its children run
in, where they can be watched and steered. Deployed to `~/.pi/agent` by the
`pi` dotfile group in `mise.toml`.

The setup follows Mario Zechner's
[case for a minimal agent](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/):
no subagent tool, no plan mode, small extensions that are read before they are
trusted. What it adds is the part pi deliberately leaves out: pi has no
permission prompts and no sandbox ([security.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/security.md)
says so), so every pi here runs inside a [nono](https://github.com/always-further/nono)
sandbox, children included.

## Layout

```
pi/                         → ~/.pi/agent/ (each file linked)
├── settings.json           Anthropic models, telemetry off, project trust "ask"
├── AGENTS.md               what the sandbox allows, how to delegate
├── extensions/
│   ├── contain.ts          claude/settings.json's deny and ask rules, as early refusals
│   └── proxy-routes.ts     points pi's Anthropic provider and MCP servers at nono's proxy
├── prompts/
│   ├── review.md           /review: a `pi -p` sub-agent reviews, Mario's pattern
│   ├── scout.md            /scout: gather context into a file for a fresh session
│   └── delegate.md         /delegate: hand a task to a pi child in a herdr pane
└── bin/                    not linked into ~/.pi/agent
    ├── pi-herdr            → ~/.local/bin; the only way a sandboxed pi drives herdr
    └── pi-credential       run by nono outside the sandbox to fetch a secret

fnox/wrapped/pi             → ~/.local/bin/wrapped/pi, first on PATH: the launcher
nono/profiles/pi-agent.jsonc → ~/.config/nono/profiles/: the sandbox
```

## How a pi starts

1. Anything that runs `pi` gets `~/.local/bin/wrapped/pi`, since mise puts that
   directory ahead of tool directories on PATH. That includes the user, and
   `herdr agent start --kind pi`, which types `pi …` into a pane's fresh login
   shell ([source](https://github.com/herdrdev/herdr/blob/main/src/app/agents.rs)),
   and herdr's session restore, which does the same.
2. The launcher resolves the real pi and nono with `mise which`, scrubs the
   `NONO_*` variables that nono would read as flags, sets `HERDR_AGENT=pi`, and
   execs `nono run --profile pi-agent --allow-cwd -- <real pi>`. No nono, no pi.
3. nono starts its supervisor and proxy outside the sandbox, applies Seatbelt,
   and runs pi in a pty of its own. That makes nono the pane's foreground
   process; herdr reads `HERDR_AGENT` from its environment
   ([source](https://github.com/herdrdev/herdr/blob/main/src/platform/mod.rs)), so
   the pane still counts as a pi agent.
4. A pi started from inside a sandbox (the `pi -p` of `/review`) sees
   `AGENT_SANDBOX=nono` and a denied `~/Library/Keychains`, and runs directly:
   it inherits the parent's sandbox and proxy routes. A pi started from Claude
   Code's sandbox refuses to start.

## Containment

| Layer | Enforced by | What it covers |
|---|---|---|
| Filesystem | nono, Seatbelt | Writable: cwd, `~/CX`, `~/CNOPS`, `~/CN-TERMINAL`, `~/dotfiles`, `~/.herdr/worktrees`, `~/.m2/repository`, caches, `~/.pi/agent` state. Read-only inside those: `~/dotfiles/{claude,fish,fnox,herdr,nono,pi,git,mise-global}`, `~/dotfiles/mise.toml`, pi's loaded config, `~/.config`, `~/.local/bin`, every `.git/hooks` and `.git/config`. Unreadable: `.env` files, keychains, 1Password, `~/.ssh`, `~/.aws`, fnox's age identities. |
| Network | nono, Seatbelt + proxy | ProxyOnly: outbound only to nono's proxy, which allows the `developer` host list plus pi.dev and herdr.dev. No raw TCP, so no SSH. Unix sockets: colima's docker.sock only. Localhost bind and connect allowed for tests. |
| Credentials | nono proxy | Anthropic, Exa and GitHub MCP are reverse-proxy routes. pi holds a per-session phantom; the proxy checks it, injects the real key (fetched by `pi-credential` outside the sandbox, from fnox), and allows only listed endpoints. |
| herdr | nono command mediation | The session never gets herdr.sock. `herdr` is reachable only through nono's shim, which allows reads and denies everything else, and starts herdr in its own sandbox that holds the socket. `pi-herdr` is the one broker for spawning, prompting, interrupting and stopping, and only for `pi-*` agents that herdr sees running pi. |
| Denied tools | nono command mediation | `gh`, `op`, `fnox`, `twg`. |
| Early refusals, approvals | `contain.ts` | Same denies with a reason the model can act on, plus Claude Code's "ask" list: force push, push --delete, reset --hard, clean -f, rebase, privileged docker; and writes to mise or direnv config. Without a UI (print mode) an ask is a refusal. |
| Conventions | `AGENTS.md`, prompts | One child per task, context gathering in its own session, commit message rules, `resign-commits` after committing. |

`contain.ts` is not a boundary: a shell string can always be rewritten to slip
past a matcher (`h=gh; $h`). Everything it refuses, nono refuses too; it is
there so the model gets a reason instead of `EPERM`, and so the ask rules have
a place to live.

### The API key

`ANTHROPIC_API_KEY` in `fnox/config.toml` is `env = false` and never reaches
pi. The obvious pi-side mechanism, `"key": "!~/.local/bin/wrapped/fnox-secret
ANTHROPIC_API_KEY"` in `auth.json`, does not work here: pi runs that command
itself, inside the sandbox, where neither the fnox daemon socket nor 1Password
is reachable. Resolving the key in the launcher and passing it as an
environment variable would work but puts it within reach of every process pi
starts. nono's [credential proxy](https://github.com/always-further/nono/blob/main/docs/cli/features/credential-injection.mdx)
keeps it out of the sandbox entirely: `credential_capture` runs
`pi-credential ANTHROPIC_API_KEY` from the unsandboxed supervisor on first use,
and pi only ever sees a phantom and a `127.0.0.1` base URL. pi ignores
`ANTHROPIC_BASE_URL` (its models carry their own `baseUrl`), so
`proxy-routes.ts` registers the override. No `auth.json` is needed.

The MCP servers work the same way. Claude Code starts the stdio
`github-mcp-server` and `exa-mcp-server` wrappers outside its sandbox; pi
starts stdio servers inside its own, where they could not fetch a token. So pi
uses the hosted endpoints instead, GitHub's remote server with
`X-MCP-Readonly` and the public-read-only token, and Exa's hosted server, each
behind a nono route. `mcp.json` cannot interpolate a URL, so `proxy-routes.ts`
registers them.

## Threat model: spawning through herdr

herdr panes start a login shell outside any sandbox, and herdr.sock controls
all of them. An agent that can talk to herdr freely is not contained. These are
the paths out that were checked, and what closes each:

| Path | Closed by |
|---|---|
| `herdr pane run`, `send-text`, `send-keys` into a shell pane | Denied by the herdr command policy; pi-herdr does not offer them. |
| `herdr agent start --kind claude` (or codex, …) with permissive flags | Denied. herdr keeps only the last `--kind`, so `--kind pi --kind claude` starts claude (verified against herdr 0.9.5); argv rules cannot express "kind is pi". pi-herdr writes `--kind pi` itself and passes the caller's arguments only after `--`. |
| `herdr pane split --env=HERDR_EXEC_CMD=…` | Denied. `fish/conf.d/50-herdr-exec.fish` evals that variable in the new pane, and `--env=` as one token evades argv matching, so the session gets no layout commands at all. pi-herdr's splits take no `--env`. |
| `herdr pane report-agent … -- <command>` | Denied (any `--`). herdr runs that command to resume the session after a restart. |
| Prompting, or sending keys to, the user's Claude or another agent | Denied directly. pi-herdr checks the target is named `pi-*` and that `herdr agent get` reports `"agent":"pi"`; herdr itself then refuses a prompt if the pane's live process is not that agent. |
| A socket client written by the agent (`nc -U`, python, curl `--unix-socket`), or a herdr binary it downloads | Seatbelt denies the connect: herdr.sock is not in the session's grants. |
| Running the real herdr binary by path | nono denies exec and read of a mediated command's binary to the session. |
| A pi child that escapes its parent's sandbox | Every child is `--kind pi`, so herdr types `pi` into a shell, which runs the launcher, which sandboxes it. If nono fails, the child does not start. |
| Widening the child's sandbox through the launcher | It takes no flags of its own, unsets `NONO_*` and `XDG_CONFIG_HOME`, and resolves nono from `$HOME`'s mise config. |
| Editing the containment or pi's config | Write-denied, including `~/.pi/agent/extensions`, `models.json` and `SYSTEM.md`, which would steer the next pi. |
| Planting a git hook, git config or shell config that the user's next command runs | Write-denied for `.git/hooks`, `.git/config`, `~/.config` and the shell-related dotfiles. |

### Not covered

- **Prompt injection and exfiltration inside the allowlist.** The proxy allows
  GitHub, the package registries and CDNs such as jsdelivr and unpkg, and
  localhost is open for tests. Anything readable can leave through an allowed
  host if the model is steered to send it. Mario's point stands: with read,
  execute and network together this is mitigation, not prevention.
- **docker.sock.** Testcontainers needs it. colima mounts only `~/CX` and
  `~/CNOPS`, already writable, so it adds no filesystem reach, but containers
  get unproxied network. `contain.ts` asks before privileged runs; the socket
  itself is open.
- **Spending.** A phantom cannot be stolen, but the agent can spend the key.
  The endpoint rules limit it to messages and models.
- **Files the user runs later.** Code, tests, `package.json` scripts, Makefiles
  and a project's `mise.toml` all run with full rights once the user runs them
  outside the sandbox. `contain.ts` asks before writes to mise and direnv
  config, but bash can write them; mise's trust prompt is the remaining check.
  `~/.m2/repository` is writable, as for Claude Code, so a poisoned artifact
  there reaches later unsandboxed builds.
- **pi-herdr's `--cwd`.** A child's login shell runs mise activation in the
  directory it starts in. pi-herdr allows only the work directories, all of
  them writable by the agent.
- **herdr reads.** `pane read` shows any pane, the user's shells included, as
  Claude Code's rules allow.
- **The marker.** `AGENT_SANDBOX` can be unset inside the sandbox; the
  wrappers then try fnox and fail. Nothing depends on it for containment.

## Choices

- **nono over a pi permission package.** [`@gotgenes/pi-permission-system`](https://github.com/gotgenes/pi-packages/tree/main/packages/pi-permission-system)
  is thorough (a bash parser, path gates, subagent forwarding), but it lives in
  the pi process, so a bash command it fails to parse, or one it never sees,
  is not contained; it also reached major version 41 in six months, and an
  auto-updating package runs inside every session. [`@erichll/pi-sandbox`](https://www.npmjs.com/package/@erichll/pi-sandbox)
  sandboxes tool calls with Anthropic's sandbox-runtime but leaves pi, its
  extensions and its credentials outside, and does not cover herdr panes at
  all. Whole-process nono plus a small extension of our own covers both.
- **pi-herdr over a herdr subagent package.** [pi-herdr-subagents](https://github.com/modem-dev/pi-herdr-subagents)
  is well made, but it needs herdr.sock inside the agent and launches children
  with `herdr plugin pane open --env PI_HERDR_LAUNCH_SCRIPT=…`, a script the
  parent writes and herdr runs unsandboxed. That is the escape this setup
  closes. A 200-line shell broker plus the `herdr` skill and `/delegate` does
  what is needed.
- **No herdr pi integration.** `herdr integration install pi` writes
  `~/.pi/agent/extensions/herdr-agent-state.ts`, which reports state by
  connecting to herdr.sock. Inside the sandbox that connect is denied, and the
  profile strips `HERDR_SOCKET_PATH` so the extension stays inert rather than
  failing on every event. herdr falls back to its pi screen manifest for
  working/idle/blocked; what is lost is session resume after a herdr server
  restart (`pi --continue` in the pane instead). Do not install it.

## Setup

1. `mise -C ~/dotfiles dot apply` links `~/.pi/agent`, the launcher, pi-herdr
   and the nono profile.
2. Create "Anthropic API Key" in the 1Password Employee vault (field
   `credential`), then `mise run sync-secrets` so the key joins the age cache
   behind the shared Touch ID.
3. `nono profile validate ~/.config/nono/profiles/pi-agent.jsonc`, then
   `nono profile show pi-agent` to see it resolved with the default groups.
4. In a herdr pane: `pi`. The first request triggers one Touch ID if the fnox
   daemon is cold. `printf '%s\n' "$AGENT_SANDBOX"` through pi's bash should
   print `nono`; `herdr pane run` should be refused.
5. `pi-herdr spawn pi-try` from that pi (ask it to), then
   `herdr agent list`: the child should show as pi, in a pane of its own.
6. Do not run `herdr integration install pi` (see above).

`/settings` cannot save: settings.json is a link into this repo, which the
sandbox makes read-only. Change `pi/settings.json` here instead.

## Tested and untested

Tested on Linux, which has no Seatbelt:

- `nono profile validate` (nono 0.80.0) and the JSON schemas of nono and pi.
- The profile under `nono run` with Landlock: the env pi gets (phantoms,
  `*_BASE_URL`, proxy, no `HERDR_SOCKET_PATH`), the credential routes end to end
  against a loopback upstream (real key injected, wrong phantom 401, endpoints
  outside the rules 403), and the herdr policy refusing `pane run`, `pane split`,
  the double `--kind` start and `report-agent … --`, and direct exec of the real
  binary.
- pi 1.4.0 inside that sandbox with these extensions and settings: the
  Anthropic provider and the GitHub MCP server went through their routes.
- `contain.ts` decisions, through jiti against a mock API.
- pi-herdr against a real herdr 0.9.5 server: spawn (quoting, `--name`,
  detection through `HERDR_AGENT`), prompt, interrupt, stop, and refusals.

Not tested, because they need macOS: the Seatbelt rules (the raw denies,
ProxyOnly, the docker.sock grant), command mediation of herdr and pi-herdr
(Linux needs a writable cgroup this machine lacks), the launcher's mise and
Keychains probes, `pi-credential` with real fnox and Touch ID, and the
hosted MCP servers.
