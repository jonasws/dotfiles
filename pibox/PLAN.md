# pibox: GitOps-provisioned Raspberry Pi 4B for pi agents

Handoff for a new session. This folder is a **draft** that is meant to move to
its own repo, `jonasws/pibox` (not created yet). It supersedes the `rpi/`
approach in dotfiles PR #8 (branch `ccr-75178189-i8ij3z`). Close that PR with
a pointer here once the repo exists.

## Goal

A headless Raspberry Pi 4B, provisioned from git with nothing built on the
device: Tailscale, mosh, Rex (server), tuios and the pi coding agent with
Anthropic as provider (default model `claude-sonnet-5-5`). A push to the repo
reaches the Pi without logging in.

## Decision: Raspberry Pi OS + cloud-init + mise bootstrap

| Considered | Outcome |
| --- | --- |
| NixOS + nvmd/nixos-raspberrypi + comin | Works and is atomic, but pi/tuios/Rex build from source unless CI feeds a binary cache. Rejected: prebuilt binaries preferred. |
| Fedora bootc / Fedora IoT | Pi support is a workaround (flash IoT, `bootc switch`); firmware not updated by bootc. Rejected. |
| **Raspberry Pi OS Lite 64-bit (trixie) + cloud-init + `mise bootstrap`** | **Chosen.** Every component has a prebuilt arm64 artifact. Not immutable and not transactional: recovery is reflash + cloud-init. |

Sources: https://mise.jdx.dev/bootstrap.html,
https://mise.jdx.dev/bootstrap/packages/apt.html,
https://mise.jdx.dev/bootstrap/systemd.html,
https://www.raspberrypi.com/news/cloud-init-on-raspberry-pi-os/,
https://www.superlogical.com/rex/docs/linux/installation.

## Prebuilt sources (checked 2026-11-14)

| Component | Source | Declared as |
| --- | --- | --- |
| OS | Raspberry Pi OS Lite 64-bit, trixie; cloud-init reads `user-data`/`network-config` on the boot partition | `cloud-init/*.example` |
| mise | `https://mise.jdx.dev/deb` stable, amd64+arm64, key fpr `24853EC9F655CE80B48E6C3A8B81C9D17413A06D` | cloud-init runcmd, then `apt:mise` |
| Tailscale | `https://pkgs.tailscale.com/stable/debian` trixie, key fpr `2596A99EAAB33821893C0A79458CA832957F5868` | `apt:tailscale` |
| mosh | Debian main | `apt:mosh` |
| Rex | `https://pkgs.superlogical.com/rex/apt`, suites `preview`/`snapshot` (amd64+arm64); **`stable` has no apt release yet**. Key fpr `E28636AC71905C6DDE40C1EDFAA6B80F641307A7` | `apt:rex`, suite `preview` |
| tuios | GitHub release `tuios_<v>_Linux_arm64.tar.gz` | `github:Gaurav-Gosain/tuios` + `asset_pattern` |
| pi | npm `@earendil-works/pi-coding-agent` (plain JS) on mise's prebuilt node 24 | `npm:` tool |

## Layout

```
mise.toml                      # whole machine: apt sources, packages, services, tools, dotfiles, sync timer, bootstrap task
config/pi-agent/               # settings.json (anthropic, claude-sonnet-5-5, cacheWarming=streaming), AGENTS.md
config/tuios/config.toml       # [agents] host_program_status = "panes"
config/rex/init.lua            # require("tuios").setup{ harness = "pi", bin = <mise shim> }
cloud-init/user-data.example   # user, ssh key, secrets via write_files, installs mise, linger, first bootstrap
cloud-init/network-config.example
```

## Flow

1. Flash Raspberry Pi OS Lite 64-bit; copy the filled `user-data` and
   `network-config` to the boot partition (secrets live only there).
2. First boot: cloud-init creates the user (passwordless sudo), writes
   `/etc/pibox/tailscale-authkey` and `~/.config/anthropic/key` (0600),
   installs mise from its apt repo, enables linger, runs
   `mise bootstrap --from https://github.com/jonasws/pibox --yes` as the user.
3. Bootstrap installs/links everything; the bootstrap task runs
   `tailscale up --ssh` once, `rex server install`, `rex skill setup --agent pi`,
   `tuios integration install pi|rex`.
4. After that, the `pibox-sync` user timer re-runs
   `mise bootstrap --from … --update --yes` every 15 minutes.
   `mise bootstrap status --missing` reports drift.

Secrets never go in git and no template uses `[bootstrap.secrets]`, so the
timer runs unattended: pi's `auth.json` holds `!cat "$HOME/.config/anthropic/key"`
(pi runs `!` commands through its shell, checked in the pi source), and
Tailscale reads the auth key file once.

## Verified in a cloud container (x86-64, mise 2026.11.8, no systemd)

- `mise bootstrap --dry-run --skip task` on `mise.toml` as a standalone repo:
  apt sources fetched and keys checked, `apt-get install mise tailscale mosh rex`,
  dotfile groups linked, `auth.json` written, tools node 24.22.3 /
  tuios 0.12.1 / pi 1.5.2 resolved. systemd units and `tailscaled` were
  skipped (no systemd in the container).
- `mise lock --platform linux-arm64` resolves tuios to
  `tuios_0.12.1_Linux_arm64.tar.gz`.

## Open items for the next session

1. Create `jonasws/pibox`, attach it (`add_repo`), move this folder's content
   to its root, and close dotfiles PR #8 with a link.
2. Fill in the TODOs in `cloud-init/user-data.example` (user name, SSH key)
   and decide Tailscale key type (one-off vs tagged, `--ssh` or not).
3. Bootstrap task guards: confirm `rex skill status` output format and whether
   `tuios integration status <x>` exits non-zero when not installed; make each
   step idempotent.
4. Rex server mode: `rex server install` (personal server) is assumed. The
   Tailscale-principal login server is documented for NixOS; check whether the
   `.deb` offers the same.
5. The sync timer runs `mise bootstrap --from <url> --update`; confirm how
   `--from` caches the checkout and that dotfile links point at a stable path
   (they must not point into a temporary clone).
6. `cloud-init` writes `~/.config/anthropic/key` with `defer: true`; confirm
   ownership and that the home directory exists at that point.
7. First real run on the Pi 4B; check `mise bootstrap status --missing`.

## Carried over from PR #8

- pi settings: `defaultProvider anthropic`, `defaultModel claude-sonnet-5-5`
  (confirm the ID with `/model`), `defaultThinkingLevel medium`,
  `cacheWarming streaming`, `enableInstallTelemetry false`.
- Rex `init.lua` has the tuios require line *without* the
  "added by tuios integration" marker, so `tuios integration install rex`
  keeps it and leaves the file alone. `bin` points at the mise shim because the
  Rex server's PATH lacks it.
- tuios `host_program_status = "panes"`: one Rex status per agent pane.
