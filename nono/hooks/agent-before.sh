#!/bin/sh
# nono before-hook for the liflig-base profile. Runs on the host, outside the
# sandbox, before the agent starts.
#
# Writes the Docker client config the agent uses. Docker sends registry
# credentials from the client to the daemon (X-Registry-Auth), so a pull-only
# token has to be readable in the sandbox; nono's proxy cannot carry it. The
# token is the classic PAT with read:packages only, kept in the keychain under
# service nono, account github_packages. It can pull from GHCR and nothing else.
#
# The agent gets its own DOCKER_CONFIG so ~/.docker (contexts pointing at
# colima, the osxkeychain credential store) never applies inside, while
# cliPluginsExtraDirs keeps `docker compose` and `docker buildx` working.

set -eu

dir="$HOME/.local/state/nono-agent/docker"
mkdir -p "$dir"
chmod 700 "$dir"

token="$(security find-generic-password -s nono -a github_packages -w 2>/dev/null || true)"
auths='{}'
if [ -n "$token" ]; then
  auth="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
  auths="{\"ghcr.io\":{\"auth\":\"$auth\"}}"
else
  echo "agent-before: no keychain item nono/github_packages; GHCR pulls will be anonymous" >&2
fi

umask 077
cat >"$dir/config.json" <<EOF
{
  "auths": $auths,
  "cliPluginsExtraDirs": ["$HOME/.docker/cli-plugins", "/opt/homebrew/lib/docker/cli-plugins"]
}
EOF

{
  echo "DOCKER_CONFIG=$dir"
  echo "DOCKER_AUTH_CONFIG={\"auths\":$auths}"
} >>"$NONO_ENV_FILE"

# Maven's settings for this session: nono/maven/proxy-settings.xml with the
# proxy port filled in. MAVEN_ARGS is set here rather than in the profile
# because it names that per-session file.
maven="$HOME/.local/state/nono-agent/maven"
mkdir -p "$maven"
if [ -n "${NONO_AGENT_PROXY_PORT:-}" ]; then
  settings="$maven/settings-$PPID.xml"
  sed "s/@NONO_AGENT_PROXY_PORT@/$NONO_AGENT_PROXY_PORT/" \
    "$HOME/dotfiles/nono/maven/proxy-settings.xml" >"$settings"
  args="-ntp -Dkotlin.compiler.daemon=false"
  args="$args -Daether.remoteRepositoryFilter.prefixes.resolvePrefixFiles.github=false"
  args="$args -Daether.remoteRepositoryFilter.prefixes.resolvePrefixFiles.flyway-community-db-support=false"
  args="$args -Dmaven.repo.local=$HOME/.m2/repository-agents -Dmaven.repo.local.tail=$HOME/.m2/repository"
  echo "MAVEN_ARGS=$args --global-settings $settings" >>"$NONO_ENV_FILE"
else
  echo "agent-before: NONO_AGENT_PROXY_PORT is unset (not started by nono/launch-agent); Maven gets no proxy" >&2
fi

# Which tuios pane and repo this nono session belongs to, keyed by the
# supervisor's pid (this hook's parent). The hook's NONO_SESSION_ID is not the
# session id nono's approval requests carry; the approval bridge
# (nono/approvals/bridge.py) maps that id to the supervisor pid through nono's
# own session record, then asks in the agent's own pane from this one.
sessions="$HOME/.local/state/nono-agent/sessions"
mkdir -p "$sessions"
workdir="${NONO_WORKDIR:-$PWD}"
repo="$(basename "$(git -C "$workdir" rev-parse --show-toplevel 2>/dev/null || echo "$workdir")")"
printf '{"pane":"%s","tuios_session":"%s","repo":"%s"}\n' \
  "${TUIOS_PANE_ID:-}" "${TUIOS_SESSION:-}" "$repo" >"$sessions/$PPID.json"
