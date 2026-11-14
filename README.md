# dotfiles

Config for a macOS (Apple silicon) work machine. The daily stack is
**Ghostty → tuios → fish → Neovim (LazyVim)**, with Claude Code agents running
in tuios panes. mise installs the tools and links this repo into `$HOME`, and
fnox keeps credentials out of the shell.

- [Daily stack](#daily-stack)
- [mise: tools, links and updates](#mise-tools-links-and-updates)
- [Credentials: fnox, 1Password and aws-vault](#credentials-fnox-1password-and-aws-vault)
- [Raspberry Pi](#raspberry-pi)
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
| `mise run update:nvim-nightly` | Reinstalls Neovim nightly for `nvn`. |

New releases wait 24 hours before mise installs them (mise's
`minimum_release_age`). That delay is the guard against a yanked or broken
`latest`. `minimum_release_age_excludes` lists the tools exempted from it:
agent tooling and small CLIs, where a same-day fix is the reason to upgrade.

**In the shell.** fish activates mise itself in `fish/conf.d/30-interactive.fish`
(`MISE_FISH_AUTO_ACTIVATE=0` keeps Homebrew's snippet from doing it late).
Non-interactive shells use the shims. mise's env also puts
`~/.local/bin/wrapped` first on `PATH`; that folder holds the fnox wrappers
below.

## Credentials: fnox, 1Password and aws-vault

No secret value lives in this repo or in the shell's environment. The full
account is in [fnox/README.md](fnox/README.md); in short:

- **1Password is the source.** [`fnox/secrets.toml`](fnox/secrets.toml) holds
  only `op://` references. `mise run sync-secrets` caches them, encrypted, in
  the untracked `~/.config/fnox/config.toml`, so reads don't go to 1Password
  each time. A rotated value stays stale until the task runs again.
- **Secrets reach one process at a time.** Secrets are `env = "exec"`, and the
  scripts in [`fnox/wrapped/`](fnox/wrapped/) (`gh`, `mvn`, `hunk`,
  `lazyjira`, the GitHub and Exa MCP servers) each export only what their one
  program needs. mise gets its GitHub token the same way, through
  `fnox-secret` as its `credential_command`.
- **One Touch ID per cold start.** The fnox daemon caches resolved secrets in
  memory for 8 idle hours, and `fnox-secret` makes all callers share a single
  decrypt.
- **Not in the sandbox.** Claude Code's sandbox can't reach 1Password, so
  anything that needs a secret runs outside it.

**AWS** has two routes, both built on one MFA session:

- [`aws/config`](aws/config) → `~/.aws/config`. The `capra-auth` profile keeps
  the IAM user keys in the macOS `login` keychain through **aws-vault**. Its
  `credential_process` hands out an MFA'd session for 12 hours, and the MFA
  code comes from 1Password (`mfa_process = op item get … --otp`). Every other
  profile assumes a role on top of it, so `AWS_PROFILE=<profile> aws …` works
  with no `aws-vault exec`. fish and nushell export
  `AWS_VAULT_KEYCHAIN_NAME=login` and `AWS_VAULT_PARALLEL_SAFE=true`.
- [`fnox-trees/`](fnox-trees/) → `~/CX`, `~/CNOPS`, `~/CN-TERMINAL`
  `fnox.toml`. Each work tree has profiles per environment and role, `build`,
  `dev`, `staging` and `prod`, each with a `--admin` variant. Each is a 1-hour
  `aws-sts` lease on top of `capra-auth`:
  `fnox -P staging exec -- aws s3 ls`.
- [`utils/aws-console`](utils/aws-console) opens the web console for a profile
  through `aws-vault login`.
- Claude Code asks before every `aws` and `fnox exec` call
  (`claude/settings.json`), and tuios marks the destructive ones
  ([tuios/README.md](tuios/README.md#agents)).

## Raspberry Pi

[`rpi/`](rpi/) sets up a Raspberry Pi to run pi agents in tuios behind a Rex
server, with Anthropic as the provider. Its dotfile groups live in
[`mise.rpi.toml`](mise.rpi.toml), which loads only with `MISE_ENV=rpi`, so
nothing above deploys there and nothing there deploys here. Setup is in
[rpi/README.md](rpi/README.md).

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
