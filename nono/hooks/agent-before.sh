#!/bin/sh
# nono before-hook for the liflig-agent profile. Runs on the host, outside the
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
