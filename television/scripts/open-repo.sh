#!/usr/bin/env bash
# Open a repository where the picker runs: a Rex session, a tuios session, a
# Herdr workspace, or a plain shell in the directory. Rex panes also set
# HERDR_ENV=1 (see fish/conf.d/45-rex-herdr.fish), and so do tuios panes, so
# REX_SESSION and TUIOS_ENV have to be checked first.
set -euo pipefail

repo_path="${1:?usage: open-repo.sh <repo_path>}"
scripts="$(dirname "$(realpath "$0")")"

if [[ -n ${REX_SESSION:-} ]]; then
  exec "$scripts/rex-session.sh" "$repo_path"
elif [[ ${TUIOS_ENV:-} == 1 ]]; then
  exec "$scripts/tuios-session.sh" "$repo_path"
elif [[ ${HERDR_ENV:-} == 1 ]]; then
  exec "$scripts/herdr-workspace.sh" "$repo_path"
else
  cd "$repo_path" && exec "${SHELL:-/bin/sh}"
fi
