# dotfiles

Config for a macOS (Apple silicon) work machine. The daily stack is
**Ghostty → tuios → fish → Neovim (LazyVim)**, with Claude Code agents running
in tuios panes. mise installs the tools and links this repo into `$HOME`, and
fnox keeps credentials out of the shell.

- [Daily stack](#daily-stack)
- [mise: tools, links and updates](#mise-tools-links-and-updates)
- [Credentials: fnox, 1Password and aws-vault](#credentials-fnox-1password-and-aws-vault)
- [Agent permission hooks](#agent-permission-hooks)
- [Kept, but not in daily use](#kept-but-not-in-daily-use)

## Daily stack

| | Config | Read more |
| - | ------ | --------- |
| Terminal | [`ghostty/`](ghostty/) | [ghostty/README.md](ghostty/README.md) |
| Multiplexer | [`tuios/`](tuios/) | [tuios/README.md](tuios/README.md) |
| Editor | [`lazyvim/`](lazyvim/) → `~/.config/nvim` | [lazyvim/README.md](lazyvim/README.md) |
| Shell | [`fish/`](fish/) | [fish/README.md](fish/README.md), plus the to-do list [fish-improvements.md](fish-improvements.md) |
| Agents | [`claude/`](claude/) | Claude Code settings, hooks, status line and the global [`CLAUDE.md`](claude/CLAUDE.md) |
| Git | [`git/`](git/) | [git/README.md](git/README.md): config, hooks and template |
| Pickers | [`television/`](television/) | tv channels behind most tuios popups; the agent session picker is described in [television/scripts/agent-sessions/README.md](television/scripts/agent-sessions/README.md) |

Smaller configs that get used: `atuin`, `bat`, `lazygit`, `yazi`, `starship`,
`nushell`, `tuicr`, `hunk`, `presenterm`, `aerospace`, `karabiner-ts`,
`keychron`, `zed`, `intellij` (`.ideavimrc`).

## mise: tools, links and updates

mise does three jobs here, configured in two files:

| File | Linked to | Holds |
| ---- | --------- | ----- |
| [`mise-global/config.toml`](mise-global/config.toml) | `~/.config/mise/config.toml` | Every CLI tool (around 100, mostly `latest`), the `nvn` and `herdrn` aliases, global env, and the `sync-secrets` task. Locked in [`mise-global/mise.lock`](mise-global/mise.lock). |
| [`mise.toml`](mise.toml) | not linked | This repo's dotfile groups and maintenance tasks. They resolve only from here: `mise run …` inside the repo, or `mise -C ~/dotfiles run …` from anywhere. |

Homebrew ([`homebrew/Brewfile`](homebrew/Brewfile)) installs the GUI apps
(Ghostty, WezTerm and others) and the few formulae mise doesn't cover.

**Linking.** Each app has a `[dotfile_groups.<app>]` entry in `mise.toml` that
says where its folder goes:

```sh
mise -C ~/dotfiles dot apply
```

Groups link file by file by default. A group with `mode = "symlink"` links the
whole directory instead (ghostty, lazyvim, tuios, yazi and others), because the
app writes back into it: `lazy-lock.json`, tuios's keybind edits. Files that
belong directly in `$HOME` are named `dot-<name>` in the repo.

**Updates.**

| Task | Does |
| ---- | ---- |
| `mise run update` | Daily: brew, mise tools (with `mise lock --global`), agent skills, nvim plugins, yazi, herdr plugins, then `git status` so changed lockfiles show. |
| `mise run update:weekly` | Adds cask upgrades with `--greedy`, `brew cleanup` and `mise prune`. |
| `mise run update:tuios-nightly` | Builds tuios from main ([tuios/README.md](tuios/README.md#installing)). |
| `mise run update:nvim-nightly` | Reinstalls Neovim nightly for `nvn` when the nightly tag has moved. |
| `mise run update:tv-nightly` | Reinstalls television (a mise tool on `branch:main`) when main has moved. |
| `mise run update:herdr-nightly` | Installs the newest herdr preview build for `herdrn`. |

New releases wait 24 hours before mise installs them (mise's
`minimum_release_age`). That delay is the guard against a yanked or broken
`latest`. `minimum_release_age_excludes` lists the tools exempted from it:
agent tooling and small CLIs, where a same-day fix is the reason to upgrade.

**In the shell.** fish activates mise itself in `fish/conf.d/30-interactive.fish`
(`MISE_FISH_AUTO_ACTIVATE=0` keeps Homebrew's snippet from doing it late).
Non-interactive shells use the shims.

## Credentials: fnox, 1Password and aws-vault

No secret value lives in this repo or in the shell's environment. The full
account is in [fnox/README.md](fnox/README.md); in short:

- **1Password is the source.** [`fnox/secrets.toml`](fnox/secrets.toml) holds
  only `op://` references. `mise run sync-secrets` caches them, encrypted, in
  the untracked `~/.config/fnox/config.toml`, so reads don't go to 1Password
  each time. A rotated value stays stale until the task runs again.
- **Secrets reach one process at a time.** In your own shells, the mise shell
  aliases `mvn` and `lazyjira` run under `fnox exec`, which injects only the
  `env = "exec"` secrets (or a profile's); mise's `credential_command` calls
  `fnox get MISE_GITHUB_TOKEN`. `gh` holds your PAT itself: run
  `gh auth login --with-token` once with `GITHUB_PERSONAL_ACCESS_TOKEN`, and
  gh, its git credential helper and hunk use it from the keychain.
- **One Touch ID per cold start.** The fnox daemon caches resolved secrets in
  memory for 8 idle hours.
- **Agents never see these.** Agents run in nono (below), which keeps its own
  copies in the keychain and adds them to requests on the host.

**AWS** has two routes, both built on one MFA session:

- [`aws/config`](aws/config) → `~/.aws/config`. The `capra-auth` profile keeps
  the IAM user keys in the macOS `login` keychain through **aws-vault**. Its
  `credential_process` hands out an MFA'd session for 12 hours, and the MFA
  code comes from 1Password (`mfa_process = op item get … --otp`). Every other
  profile assumes a role on top of it, so `AWS_PROFILE=<profile> aws …` works
  with no `aws-vault exec`. fish and nushell export
  `AWS_VAULT_KEYCHAIN_NAME=login` and `AWS_VAULT_PARALLEL_SAFE=true`. Role
  profiles omit `mfa_serial` on purpose, and aws-vault doesn't inherit it from
  `source_profile`, so the fish `aws-vault` function
  ([`fish/functions/aws-vault.fish`](fish/functions/aws-vault.fish)) defaults
  `AWS_MFA_SERIAL` for direct `aws-vault exec|login` calls. `credential_process`
  and the AWS CLI don't go through it and don't need it.
- [`fnox-trees/`](fnox-trees/) → `~/CX`, `~/CNOPS`, `~/CN-TERMINAL`
  `fnox.toml`. Each work tree has profiles per environment and role, `build`,
  `dev`, `staging` and `prod`, each with a `--admin` variant. Each is a 1-hour
  `aws-sts` lease on top of `capra-auth`:
  `fnox -P staging exec -- aws s3 ls`.
- [`utils/aws-console`](utils/aws-console) (fish: `console <profile>`) opens the
  web console for a profile in a Firefox container. The `aws` CLI resolves the
  profile through `capra-auth`'s session, [Granted](https://docs.commonfate.io/granted/usage/console)
  (`granted console`) builds the sign-in URL, and its Firefox add-on opens the
  container. aws-vault is no longer involved, so there is no extra MFA prompt.
  The `color` key in `aws/config` sets the container colour.
- `<account>-<env>-readonly` and `-agent` profiles in [`aws/config`](aws/config)
  narrow the developer role's session with STS GetScopedCredentials, through
  [`bin/aws-scoped-credentials`](bin/aws-scoped-credentials) and the policies
  in [`aws/policies/`](aws/policies). The identity in CloudTrail stays the
  developer session. `-readonly` allows control-plane reads only; `-agent` is
  the developer role minus IAM writes, role assumption, secret values and the
  common deletes. The AWS MCP Server (`aws` in
  [`claude/mcp-servers.json`](claude/mcp-servers.json)) signs with these
  `-readonly` profiles, and `aws-mcp-guard.py` lets `run_script` run without
  asking on those. Needs aws-cli 2.41.2 or later and `sts:GetScopedCredentials`
  on the role.
- **Agents in nono.** Plain `claude` and `pi` start inside nono: the
  stand-ins in [`tuios/shims/`](tuios/shims), first on `PATH`, run
  [`nono/launch-agent`](nono/launch-agent), which picks the `liflig-agent`
  or `liflig-pi` profile ([`nono/profiles/`](nono/profiles), both on
  `liflig-base`), drops the tuios pane to `read,write` and sets
  `TUIOS_AGENT` so tuios still recognises the harness behind nono. A shell,
  `tuios start-agent`, presets and `fan` all reach it by name; outside nono
  only on purpose, with `command (mise which claude)`. No credential of yours enters the sandbox:
  each tool finds its usual variable (`GH_TOKEN`, `LIFLIG_GITHUB_PAT`,
  `NEXUS_PASSWORD`, `CONTEXT7_API_KEY`, `EXA_API_KEY`, ...) set to a
  placeholder, and nono's proxy, on the host, swaps in the real value. git
  fetch (no push), `gh` and the github MCP (public reads), Maven against
  GitHub Packages and Nexus (reads only), Context7, Exa and read-only AWS
  (several profiles; generated by `mise run nono:gen-aws`) work with no
  wrapper. Maven gets nono's proxy from
  [`nono/maven/proxy-settings.xml`](nono/maven/proxy-settings.xml) and trusts
  its CA through a truststore built once. Hosts not on the profile's list are
  asked in tuios: [`nono/approvals/bridge.py`](nono/approvals/bridge.py), a
  LaunchAgent, turns nono's approval request into `tuios ask-human` on the
  agent's own pane (allow once, allow for the session, deny). Docker is a Lima
  VM of the agents' own ([`lima/agents.yaml`](lima/agents.yaml): rootless,
  read-only repo mounts, no route to the Mac). Agents get their own mise,
  Maven, npm, uv, Go and cargo caches, and read yours, so nothing they
  download runs in your shell later. `~/dotfiles` is read-only to them.
  One-time setup: `mise run nono:keychain` (with `NONO_GITHUB_PACKAGES` set to
  a `read:packages` PAT), `mise run nono:java-truststore`,
  `mise run sync:nono-approvals` and `mise run lima:agents`. The design, with
  diagrams: [`docs/agent-fleet-sandbox.tml`](docs/agent-fleet-sandbox.tml)
  (`mise run claude:explain-sandbox`).
- Claude Code asks before every `aws` and `fnox exec` call
  (`claude/settings.json`), and tuios marks the destructive ones
  ([tuios/README.md](tuios/README.md#agents)).

## Agent permission hooks

[`claude/settings.json`](claude/settings.json) registers PreToolUse hooks from
[`claude/hooks/`](claude/hooks/), which `mise dot apply` links into
`~/.claude/hooks` one file at a time. Link a new hook before registering it: a
missing script blocks every Bash call. `mise run claude:explain-hooks` opens
[`overview.tml`](claude/hooks/overview.tml), a table of what each hook and rule
allows, asks about or denies. Its counts are kept by hand.

| Hook | Decides | What |
| ---- | ------- | ---- |
| `pane-control-guard.py` | ask | Pane control through tuios or herdr: reading, typing, launching, closing. It is the only gate for these: settings has no tuios or herdr ask rules. A `tuios split-window` or `new-window` that only opens a viewer after `--` passes. The viewers are pagers (`leaf`, `less`, `bat`, `cat`), log viewers (`lnav`, `gonzo`, `tspin`, `hl`), JSON viewers (`fx` with one file, `otree`) and `nvim -R`. Each passes only with its own allow-listed flags, so flags that run commands, send data out or write files still ask. |
| `help-allow.py` | allow, ask | Allows commands that are only `--help`, `-h`, `--version` or `help` (rules in `help_only.py`). It asks for every other `twg` command, in place of a `Bash(twg:*)` rule that would also catch `twg … --help`. |
| `inline-script-guard.py` | deny | No `python3 -c`, `node -e` or heredoc programs. |
| `aws-mcp-guard.py` | allow, ask | AWS MCP scripts: run without asking on a profile scoped read-only by `aws-scoped-credentials`, ask on any other profile. IAM enforces the scope, so the hook does not read the script. |
| `repl-lint.sh` | deny | Lints REPL scripts with ast-grep. |
| `researcher-bash-guard.py` | deny | The `researcher` agent runs only find-docs commands. |

An ask from a settings rule outranks a hook's allow, so an ask rule cannot
exempt `--help`. That is why the twg and pane-control checks live in hooks.
Each guard has a self-test: `python3 -I claude/hooks/<hook>.py --self-test`.

## Kept, but not in daily use

- **WezTerm** (`wezterm/`): still installed. It was the tuios host until
  Ghostty took over on 2026-11-02.
- **herdr** (`herdr/`): installed by mise. tuios runs herdr's plugins and
  answers its socket API, so `herdr/` still supplies plugin config and scripts.
- **Rex** (`rex/`, [rex/README.md](rex/README.md)): the app is no longer
  installed. Its config and herdr bridge are still deployed.
- **tmux, zellij**: configs kept, not in use.
- **Old editors**: `nvim-kickstart`, `vim`, `doom`, `spacemacs`, `atom`, `vscode`.
- **Other machines and shells**: `i3`, `xbindkeys`,
  `remap_escape_and_prtscr.sh` and `kb-layouts` are from Linux; `hyper` and
  `iterm2` are older macOS terminals; `zsh` and `bash` are the non-fish shells.
