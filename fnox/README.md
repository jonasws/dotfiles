# fnox Configuration

Machine-wide [fnox](https://fnox.jdx.dev) configuration, deployed by the `fnox` dotfile group in `mise.toml`.

## Structure

```
fnox/                  # deployed to ~/.config/fnox/
├── config.toml        # providers, secrets, profiles — references only
└── wrapped/           # deployed to ~/.local/bin/wrapped/
```

`~/.config/fnox/age.txt` (the age identity) lives next to the linked config but is
deliberately not in this repository.

## Setup

From the dotfiles root:

```sh
mise dot apply
```

This symlinks `fnox/config.toml` to `~/.config/fnox/config.toml`.

## Design rules

- **References only.** `config.toml` holds `op://` references, never secret values,
  so it is safe to commit to a public repository.
- **No sync blobs.** `fnox sync` writes an encrypted `sync = { ... }` sub-table into
  the config file it targets. For the global config that file is this tracked one,
  so a sync would publish ciphertext to GitHub and add noise to every later diff.
  This repository stays sync-free; see below for the ad-hoc alternative.
- **`env = "exec"`.** Secrets are injected only into `fnox exec` subprocesses, so an
  interactive shell — and anything launched from it — inherits nothing.

## Local caching without touching the config

The per-user daemon already caches resolved secrets in memory, which is what makes
repeated reads fast without a 1Password round trip. It is enabled in `config.toml`
with an 8 hour idle timeout, and it stores nothing on disk.

```sh
fnox daemon status    # running?  how many entries cached?
fnox daemon clear     # drop the caches of all running daemons
fnox daemon stop      # stop it; the next fnox call starts a fresh one
```

A single secret (or a whole provider) can opt out of caching with
`daemon_cache = false` on its entry, which forces a direct resolve every time.

## Ad-hoc sync, per secret

`fnox sync` takes secret keys positionally, so a sync can be scoped to exactly one
value:

```sh
fnox sync --provider sync-age --global --dry-run MISE_GITHUB_TOKEN
```

It requires an encryption provider as its target (`age`, `aws-kms`, `azure-kms`,
`gcp-kms`); reference providers such as `1password` and `keychain` are rejected with
`Provider 'onepass' cannot be used as a sync target`. That means adding a
`[providers.sync-age]` block here first — a config change of its own — and the run
then rewrites each named secret in place:

```toml
MISE_GITHUB_TOKEN = { provider = "onepass", value = "op://...", sync = { provider = "sync-age", value = "YWdlLWVuY3J5cHRpb24..." } }
```

There is no way to keep that out of the tracked file. The global config has no
local-override sibling: `~/.config/fnox/config.local.toml` is not loaded (`fnox
config-files` lists `config.toml` alone), and `--local-file` refuses an explicit
path with

```
--local-file requires --config to be the bare filename 'fnox.toml' or '.fnox.toml'
```

So if a sync is ever genuinely needed here, treat it as disposable: run it, use it,
then throw the edits away with `git checkout fnox/config.toml`. There
is no unsync command — removing a `sync` sub-table is a manual edit.

Project-level configs are the place where syncing is actually comfortable: a
`fnox.toml` in a repository can sync to a gitignored `fnox.local.toml` with
`fnox sync --provider sync-age --local-file`, keeping the ciphertext out of version
control entirely.

## Profiles

Profiles scope an injection to one consumer. Combined with `--no-defaults`, the
command receives that profile's secrets and nothing else:

```sh
fnox exec -P gh --no-defaults -- gh pr list       # GH_TOKEN only
fnox get -P gcalcli --no-defaults GCALCLI_CLIENT_ID
```

`fnox profiles` lists them.

## Touch ID: one per cold start

Every profile has its own daemon and its own sync blob, so each profile read cold
costs a Secure Enclave decrypt and a Touch ID. The secrets read at Claude Code
startup — the github and Exa MCP tokens, and mise's GitHub token — are therefore
top-level `env = false` secrets, fetched through `wrapped/fnox-secret`. Its header
explains the three flags that make all of its callers share one decrypt: `-c`
for a fingerprint that does not change per directory tree, `export --all` to
resolve the whole blob at once, and `--non-interactive` to serialise parallel
callers in the daemon.

After adding or rotating a top-level secret, `mise run sync-secrets` re-encrypts
them all into one blob.
