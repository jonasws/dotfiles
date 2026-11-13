#!/usr/bin/env bash
# Hermes Agent on the Pi, reachable over Signal, with mise owning signal-cli
# and its Java.
#
# Run on the Pi as your normal (sudo-capable) user, from this directory:
#
#   ./setup.sh                  # clean up an earlier install, then install
#   ./setup.sh --keep-data      # same, but keep ~/.hermes config, keys and memory
#   ./setup.sh --dry-run        # only report what the cleanup would remove
#   ./setup.sh --reinstall      # clean up and reinstall an install made by this script
#
# 1. Cleanup. Finds what the earlier curl-installer route left behind: the
#    gateway's systemd units (user and system), the Hermes checkout, its tool
#    store and launcher, and a hand-installed signal-cli under /opt. That is
#    checked both for the `hermes` user and for you, in case the installer ran
#    as you. ~/.hermes is archived before anything is removed. An install this
#    script made (it has ~hermes/.config/hermes-pi) is left alone on a rerun,
#    unless --reinstall.
# 2. Install. Packages from apt, the `hermes` user (no sudo, lingering), mise
#    and its config (mise.toml here), signal-cli and Java through mise, then
#    Hermes through `mise run hermes:install`.
# 3. Signal. Links signal-cli to your phone as a secondary device (QR code),
#    starts its daemon on loopback, and points Hermes at it, allowing only your
#    own number. You talk to the agent through "Note to Self".
# 4. Model and gateway. `hermes model` (interactive), then the gateway as a
#    systemd user service that starts after signal-cli.
#
# Everything after the cleanup is idempotent, so a failed run can be rerun.

set -euo pipefail

HERMES_USER=hermes
SIGNAL_HTTP_ADDR=127.0.0.1:18080
HERE=$(cd "$(dirname "$0")" && pwd)
KEEP_DATA=false
REINSTALL=false
DRY_RUN=false
ASSUME_YES=false
SIGNAL_ACCOUNT=

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  echo "Options: --keep-data  --reinstall  --dry-run  --yes  --account +4712345678"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-data) KEEP_DATA=true ;;
    --reinstall) REINSTALL=true ;;
    --dry-run) DRY_RUN=true ;;
    --yes | -y) ASSUME_YES=true ;;
    --account) SIGNAL_ACCOUNT=${2:?--account needs a number in E.164 form}; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
confirm() {
  $ASSUME_YES && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY]* ]]
}

# ── Preflight ───────────────────────────────────────────────────────────────

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root; it uses sudo where it must"
command -v sudo >/dev/null || die "sudo is required"
command -v systemctl >/dev/null || die "systemd is required"
for f in mise.toml libsignal-arm64.sh signal-cli.service hermes-gateway-signal.conf; do
  [ -f "$HERE/$f" ] || die "$f is missing beside setup.sh"
done
case "$(uname -m)" in
  aarch64) ;;
  armv7l | armv6l) die "this is a 32-bit OS; Hermes and signal-cli need 64-bit Raspberry Pi OS" ;;
  *) warn "not an aarch64 machine ($(uname -m)); continuing anyway" ;;
esac
sudo -v

home_of() { getent passwd "$1" | cut -d: -f6; }
uid_of() { id -u "$1"; }

# Run a command as USER with that user's systemd user manager reachable, so
# `systemctl --user` and `hermes gateway install` work from sudo.
as_user() {
  local user=$1 uid home
  shift
  uid=$(uid_of "$user")
  home=$(home_of "$user")
  sudo -u "$user" -H env \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    PATH="$home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    bash -c "cd ~ && $*"
}

user_manager_up() { [ -S "/run/user/$(uid_of "$1")/bus" ]; }

# ── 1. Cleanup ──────────────────────────────────────────────────────────────

# Users whose home may hold an earlier install: the service user, and you.
candidates=()
id "$HERMES_USER" >/dev/null 2>&1 && candidates+=("$HERMES_USER")
[ "$(id -un)" != "$HERMES_USER" ] && candidates+=("$(id -un)")

found=()
for user in "${candidates[@]}"; do
  home=$(home_of "$user")
  for path in \
    "$home/.hermes" \
    "$home/.local/bin/hermes" \
    "$home/.config/systemd/user/hermes-gateway.service" \
    "$home/.config/systemd/user/hermes.service" \
    "$home/.config/systemd/user/signal-cli.service"; do
    sudo test -e "$path" && found+=("$path")
  done
done
for path in /etc/systemd/system/hermes-gateway*.service /etc/systemd/system/hermes.service; do
  [ -e "$path" ] && found+=("$path")
done
manual_signal=()
if [ -L /usr/local/bin/signal-cli ] && [[ $(readlink /usr/local/bin/signal-cli) == /opt/signal-cli* ]]; then
  manual_signal+=(/usr/local/bin/signal-cli)
fi
for d in /opt/signal-cli /opt/signal-cli-*; do [ -e "$d" ] && manual_signal+=("$d"); done

say "Cleanup of an earlier install"
ours=false
id "$HERMES_USER" >/dev/null 2>&1 && sudo test -d "$(home_of "$HERMES_USER")/.config/hermes-pi" && ours=true
if $ours && ! $REINSTALL; then
  note "the existing install was made by this script; keeping it (--reinstall to redo)"
  $DRY_RUN && exit 0
elif [ ${#found[@]} -eq 0 ] && [ ${#manual_signal[@]} -eq 0 ]; then
  note "nothing found"
  $DRY_RUN && exit 0
else
  for p in "${found[@]}" "${manual_signal[@]}"; do note "found $p"; done
  if $KEEP_DATA; then
    note "--keep-data: ~/.hermes config, .env, memories and tokens stay; code, tools and units go"
  else
    note "~/.hermes is archived to ~/hermes-backup-<time>.tar.gz, then removed"
  fi
  note "signal-cli's own data (~/.local/share/signal-cli, the linked-device keys) is kept"
  if $DRY_RUN; then
    note "--dry-run: nothing removed"
    exit 0
  fi
  confirm "Remove these?" || die "stopped; nothing was removed"

  # System-wide gateway units (`sudo hermes gateway install --system`).
  for unit in /etc/systemd/system/hermes-gateway*.service /etc/systemd/system/hermes.service; do
    [ -e "$unit" ] || continue
    name=$(basename "$unit")
    sudo systemctl disable --now "$name" 2>/dev/null || true
    sudo rm -f "$unit"
    note "removed system unit $name"
  done
  sudo systemctl daemon-reload

  stamp=$(date +%Y%m%d-%H%M%S)
  for user in "${candidates[@]}"; do
    home=$(home_of "$user")
    units=$(sudo bash -c "ls '$home'/.config/systemd/user/ 2>/dev/null" | grep -E '^(hermes(-gateway[^.]*)?|signal-cli)\.service$' || true)
    if [ -n "$units" ]; then
      if user_manager_up "$user"; then
        # shellcheck disable=SC2086
        as_user "$user" systemctl --user disable --now $units 2>/dev/null || true
      fi
      for name in $units; do
        sudo rm -rf "$home/.config/systemd/user/$name" "$home/.config/systemd/user/$name.d"
        note "removed $user's user unit $name"
      done
      user_manager_up "$user" && as_user "$user" systemctl --user daemon-reload || true
    fi
    # A gateway started by hand (`hermes gateway` in a shell) has no unit.
    sudo pkill -u "$user" -f 'hermes(-agent)?.* gateway' 2>/dev/null && note "stopped a running gateway of $user" || true

    if sudo test -d "$home/.hermes"; then
      archive="$home/hermes-backup-$stamp.tar.gz"
      # Config, .env (API keys), memories, skills, sessions, MCP tokens; not the
      # code checkout, the tool store or caches, which reinstall.
      sudo tar -C "$home" -czf "$archive" \
        --exclude=.hermes/hermes-agent --exclude=.hermes/tools \
        --exclude=.hermes/image_cache --exclude=.hermes/audio_cache --exclude=.hermes/logs \
        .hermes
      sudo chown "$user:" "$archive"
      sudo chmod 600 "$archive"
      note "archived $user's ~/.hermes to $archive"
      if $KEEP_DATA; then
        sudo rm -rf "$home/.hermes/hermes-agent" "$home/.hermes/tools"
      else
        sudo rm -rf "$home/.hermes"
      fi
    fi
    sudo rm -f "$home/.local/bin/hermes"
    sudo rm -rf "$home/.config/hermes-pi"
  done

  for p in "${manual_signal[@]}"; do
    sudo rm -rf "$p"
    note "removed $p"
  done
fi

# ── 2. Install ──────────────────────────────────────────────────────────────

say "System packages"
# qrencode draws the Signal link; zip/unzip patch the libsignal jar;
# systemd-container gives `machinectl shell hermes@`; libatomic1
# is needed by the Node.js Hermes's installer provisions.
sudo apt-get update -qq
sudo apt-get install -y -qq git curl tar xz-utils zip unzip qrencode systemd-container libatomic1 ca-certificates >/dev/null
note "done"

say "The $HERMES_USER user"
if ! id "$HERMES_USER" >/dev/null 2>&1; then
  # Its own group only, no sudo: a bad tool call can damage the agent's files,
  # not the machine.
  sudo useradd -m -s /bin/bash "$HERMES_USER"
  note "created"
fi
if id -nG "$HERMES_USER" | tr ' ' '\n' | grep -qxE 'sudo|wheel|adm'; then
  warn "$HERMES_USER is in an admin group ($(id -nG "$HERMES_USER")); remove it with: sudo gpasswd -d $HERMES_USER sudo"
fi
# Lingering keeps its user services running without a login, and from boot.
sudo loginctl enable-linger "$HERMES_USER"
for _ in $(seq 1 20); do user_manager_up "$HERMES_USER" && break; sleep 0.5; done
user_manager_up "$HERMES_USER" || die "the user manager for $HERMES_USER did not start"
HHOME=$(home_of "$HERMES_USER")
note "home $HHOME, lingering"

say "mise and its config"
as_user "$HERMES_USER" 'mkdir -p ~/.config/mise ~/.config/hermes-pi ~/.config/systemd/user/hermes-gateway.service.d'
sudo install -o "$HERMES_USER" -g "$HERMES_USER" -m 0644 "$HERE/mise.toml" "$HHOME/.config/mise/config.toml"
sudo install -o "$HERMES_USER" -g "$HERMES_USER" -m 0755 "$HERE/libsignal-arm64.sh" "$HHOME/.config/hermes-pi/libsignal-arm64.sh"
if ! sudo test -x "$HHOME/.local/bin/mise"; then
  as_user "$HERMES_USER" 'tmp=$(mktemp) && curl -fsSL https://mise.run -o "$tmp" && sh "$tmp" && rm -f "$tmp"'
fi
as_user "$HERMES_USER" 'mise --version'

say "Java and signal-cli (mise install)"
as_user "$HERMES_USER" 'MISE_YES=1 mise install'
as_user "$HERMES_USER" 'mise exec -- signal-cli --version'

say "Hermes (mise run hermes:install)"
as_user "$HERMES_USER" 'mise run hermes:install'
as_user "$HERMES_USER" 'command -v hermes' >/dev/null || die "hermes is not on $HERMES_USER's PATH after install"

# ── 3. Signal ───────────────────────────────────────────────────────────────

say "Signal"
# signal-cli holds its data directory while the daemon runs.
as_user "$HERMES_USER" 'systemctl --user stop signal-cli.service 2>/dev/null || true'
linked=$(as_user "$HERMES_USER" 'mise exec -- signal-cli -o json listAccounts 2>/dev/null' | grep -oE '\+[0-9]{6,15}' || true)
if [ -n "$linked" ]; then
  note "signal-cli is already linked to: $linked"
else
  note "On your phone: Signal → Settings → Linked devices → Link new device, then scan:"
  as_user "$HERMES_USER" 'mise run signal:link'
  linked=$(as_user "$HERMES_USER" 'mise exec -- signal-cli -o json listAccounts 2>/dev/null' | grep -oE '\+[0-9]{6,15}' || true)
fi
if [ -z "$SIGNAL_ACCOUNT" ]; then
  default=$(printf '%s\n' "$linked" | head -n 1)
  read -r -p "Signal account number (E.164) [${default}]: " SIGNAL_ACCOUNT
  SIGNAL_ACCOUNT=${SIGNAL_ACCOUNT:-$default}
fi
[[ $SIGNAL_ACCOUNT =~ ^\+[0-9]{6,15}$ ]] || die "not an E.164 number: '$SIGNAL_ACCOUNT'"

# The daemon's settings, read by signal-cli.service.
printf 'SIGNAL_ACCOUNT=%s\nSIGNAL_HTTP_ADDR=%s\n' "$SIGNAL_ACCOUNT" "$SIGNAL_HTTP_ADDR" |
  sudo tee "$HHOME/.config/hermes-pi/signal.env" >/dev/null
sudo chown "$HERMES_USER:" "$HHOME/.config/hermes-pi/signal.env"
sudo chmod 600 "$HHOME/.config/hermes-pi/signal.env"

sudo install -o "$HERMES_USER" -g "$HERMES_USER" -m 0644 "$HERE/signal-cli.service" "$HHOME/.config/systemd/user/signal-cli.service"
as_user "$HERMES_USER" 'systemctl --user daemon-reload && systemctl --user enable signal-cli.service && systemctl --user restart signal-cli.service'
note "waiting for the signal-cli daemon on $SIGNAL_HTTP_ADDR (the JVM is slow to start on a Pi)"
for _ in $(seq 1 90); do
  curl -fsS "http://$SIGNAL_HTTP_ADDR/api/v1/check" >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS "http://$SIGNAL_HTTP_ADDR/api/v1/check" || die "signal-cli did not come up: sudo journalctl _UID=$(uid_of "$HERMES_USER") -u signal-cli -n 50"
echo

# Hermes's Signal settings, in ~/.hermes/.env. Only your own number may talk to
# it, and cron results are delivered there too ("Note to Self").
# https://hermes-agent.nousresearch.com/docs/user-guide/messaging/signal
set_env() {
  local key=$1 value=$2 file="$HHOME/.hermes/.env"
  sudo test -f "$file" || { sudo install -o "$HERMES_USER" -g "$HERMES_USER" -m 600 /dev/null "$file"; }
  if sudo grep -qE "^#?\s*$key=" "$file"; then
    sudo sed -i -E "s|^#?\s*$key=.*|$key=$value|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" | sudo tee -a "$file" >/dev/null
  fi
}
set_env SIGNAL_HTTP_URL "http://$SIGNAL_HTTP_ADDR"
set_env SIGNAL_ACCOUNT "$SIGNAL_ACCOUNT"
set_env SIGNAL_ALLOWED_USERS "$SIGNAL_ACCOUNT"
set_env SIGNAL_HOME_CHANNEL "$SIGNAL_ACCOUNT"
note "Hermes configured for Signal as $SIGNAL_ACCOUNT"

# ── 4. Model and gateway ────────────────────────────────────────────────────

say "Model provider"
note "Use an API key with a spend limit, not a Claude subscription login."
if confirm "Run 'hermes model' now to choose a provider and model?"; then
  as_user "$HERMES_USER" 'hermes model'
else
  note "later: sudo -iu $HERMES_USER hermes model"
fi

say "Gateway service"
as_user "$HERMES_USER" 'hermes gateway install --force'
sudo install -o "$HERMES_USER" -g "$HERMES_USER" -m 0644 "$HERE/hermes-gateway-signal.conf" \
  "$HHOME/.config/systemd/user/hermes-gateway.service.d/10-signal.conf"
as_user "$HERMES_USER" 'systemctl --user daemon-reload && systemctl --user restart hermes-gateway.service'
sleep 5
as_user "$HERMES_USER" 'systemctl --user --no-pager --lines=0 status signal-cli.service hermes-gateway.service' || true

say "Done"
note "Send yourself a message in Signal's \"Note to Self\"; Hermes answers there."
note "Logs:     sudo journalctl _UID=$(uid_of "$HERMES_USER") -f"
note "Shell:    sudo machinectl shell $HERMES_USER@   (has the user bus, so systemctl --user works)"
note "Upgrade:  mise run upgrade, in that shell; monthly at least, as old signal-cli stops working"
