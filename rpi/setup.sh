#!/usr/bin/env bash
# Wires pi, tuios and Rex together on a Raspberry Pi. Installs nothing: it
# checks that the tools are there and stops if any is missing.
# See rpi/README.md.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
fail() { printf 'rpi/setup.sh: %s\n' "$*" >&2; exit 1; }

# ── Checks ──────────────────────────────────────────────────────────────────
[ "$(uname -m)" = aarch64 ] || fail "needs a 64-bit OS (aarch64); Rex has no 32-bit ARM build"
[ "$repo" = "$HOME/dotfiles" ] || fail "clone the repo to ~/dotfiles (mise.toml sets dotfiles.root there), not $repo"

require() {
  local missing=() bin
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
  done
  [ ${#missing[@]} -eq 0 ] || fail "not found on PATH: ${missing[*]}
  $hint"
}

hint="mise: https://mise.jdx.dev/installing-mise.html
  rex: https://www.superlogical.com/rex/docs/linux/installation"
require mise rex
# mise's shims, so tools from `mise install` are found without `mise activate`.
export PATH="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims:$PATH"
rex ls >/dev/null 2>&1 || fail "no Rex server answers; run 'rex server install' once, then re-run this"

# ── Dotfiles ────────────────────────────────────────────────────────────────
# Links ~/.config/mise/config.toml too, which declares node, pi and tuios.
mise trust --quiet "$repo/mise.toml"
mise trust --quiet "$repo/mise.rpi.toml"
MISE_ENV=rpi mise -C "$repo" dot apply

# Checked after the link, so a first run says how to get them.
hint="run 'mise install' (rpi/mise/config.toml), then re-run this"
require node pi tuios
node_major="$(node -p 'process.versions.node.split(".")[0]')"
[ "$node_major" -ge 22 ] || fail "pi needs Node 22.19 or newer, found $(node --version)"

# ── Anthropic API key ───────────────────────────────────────────────────────
# auth.json (from the rpi-pi group) reads the key from this file at run time,
# so no key is in the repo or in any shell's environment.
keyfile="$HOME/.config/anthropic/key"
if [ ! -s "$keyfile" ]; then
  [ -t 0 ] || fail "$keyfile is missing; run this in a terminal to enter the key"
  mkdir -p "$(dirname "$keyfile")"
  chmod 700 "$(dirname "$keyfile")"
  read -rsp 'Anthropic API key: ' key; echo
  [ -n "$key" ] || fail "no key entered"
  (umask 077; printf '%s' "$key" > "$keyfile")
fi
chmod 600 "$keyfile"

# ── Integrations ────────────────────────────────────────────────────────────
rex skill setup --agent pi          # ~/.agents/skills/rex
tuios integration install pi        # state extension in ~/.pi/agent/extensions + tuios skill
tuios integration install rex       # tuios.lua beside ~/.config/rex/init.lua, then rex config reload
tuios doctor agents
