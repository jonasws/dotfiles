# fnox Configuration

Machine-wide [fnox](https://fnox.jdx.dev) configuration, deployed by the `fnox` dotfile group in `mise.toml`.

## Structure

```
fnox/                  # deployed to ~/.config/fnox/
├── secrets.toml       # providers, secrets, profiles — references only
└── wrapped/           # deployed to ~/.local/bin/wrapped/
```

`~/.config/fnox/config.toml` is the file fnox loads, and it is not in this
repository: it imports `secrets.toml` and holds the local sync cache. `age.txt` and
`age-se.txt` (the age identities) sit beside it, also untracked.

## Setup

From the dotfiles root:

```sh
mise dot apply          # links fnox/secrets.toml into ~/.config/fnox/
mise run sync-secrets   # writes ~/.config/fnox/config.toml and fills the cache
```

## Design rules

- **References only.** `secrets.toml` holds `op://` references, never secret values,
  so it is safe to commit to a public repository.
- **The sync cache stays out of git.** `fnox sync` writes an encrypted
  `sync = { ... }` sub-table into the config file it targets. With `--global` that
  is `~/.config/fnox/config.toml`, the untracked file that imports `secrets.toml`.
- **`env = "exec"`.** Secrets are injected only into `fnox exec` subprocesses, so an
  interactive shell — and anything launched from it — inherits nothing.

## Local caching

The per-user daemon caches resolved secrets in memory with an 8 hour idle timeout,
and stores nothing on disk.

```sh
fnox daemon status    # running?  how many entries cached?
fnox daemon clear     # drop the caches of all running daemons
fnox daemon stop      # stop it; the next fnox call starts a fresh one
```

A single secret (or a whole provider) can opt out of caching with
`daemon_cache = false` on its entry, which forces a direct resolve every time.

`mise run sync-secrets` adds a cache on disk: it re-encrypts every top-level secret
with the `sync-age` provider into `~/.config/fnox/config.toml`, so reads stop
reaching 1Password.

The global config has no local-override sibling (`config.local.toml` is not loaded,
and `--local-file` only works beside a project `fnox.toml`), hence the import. The
catch: fnox merges secrets whole, not field by field, so sync copies each entry
complete with `provider`, `value` and `env`, and that copy shadows the definition in
`secrets.toml`. The task therefore rebuilds `config.toml` from scratch on every
run. After editing, adding or removing a secret in `secrets.toml`, run it again;
until then the old entry keeps resolving. Anything written with
`fnox set --global` lands in the untracked file and is wiped by the next run, so
add secrets to `secrets.toml` instead.

## Profiles

Profiles scope an injection to one consumer. Combined with `--no-defaults`, the
command receives that profile's secrets and nothing else:

```sh
fnox get -P gcalcli --no-defaults GCALCLI_CLIENT_ID
```

`fnox profiles` lists them.

## Touch ID: one per cold start

Every profile has its own daemon and its own sync blob, so each profile read cold
costs a Secure Enclave decrypt and a Touch ID. The secrets read at Claude Code
startup — the github and Exa MCP tokens, gh's token (Claude Code runs gh on its
own), and mise's GitHub token — are therefore
top-level `env = false` secrets, fetched through `wrapped/fnox-secret`. Its header
explains the three flags that make all of its callers share one decrypt: `-c`
for a fingerprint that does not change per directory tree, `export --all` to
resolve the whole blob at once, and `--non-interactive` to serialise parallel
callers in the daemon.

After adding or rotating a top-level secret, `mise run sync-secrets` re-encrypts
them all into one blob.
