#!/usr/bin/env bash
# Prefetch a Maven project's dependencies, plugins and dependency sources into
# ~/.m2/repository, so agents can read a library's source at the exact version
# the build uses, without the network. Agents read that repository (directly,
# or as the read-only tail of their own); the find-docs skill reads the
# -sources.jar files it finds there.
#
#   mise run forge:maven [DIR...]     # default: the current directory
#
# Run it on the host, where your Maven credentials are: it goes through
# `fnox exec` like the interactive mvn alias, so GitHub Packages and Nexus
# resolve. Re-run after changing dependencies; it only downloads what is new.
#
# qaware's go-offline plugin rather than maven-dependency-plugin: in a
# multi-module build, dependency:sources resolves sibling modules from the
# remote repositories and fails, and dependency:go-offline ignores a sources
# classifier for project dependencies. qaware's plugin skips reactor modules and
# fetches sources with -DdownloadSources. Plugins that load dependencies at run
# time (surefire's providers, for one) still fetch those on the first build.
set -euo pipefail

plugin=de.qaware.maven:go-offline-maven-plugin:1.2.8:resolve-dependencies
mvn=(mvn -B -ntp)
command -v fnox >/dev/null && mvn=(fnox exec -- mvn -B -ntp)
logs="${XDG_CACHE_HOME:-$HOME/.cache}/forge"
mkdir -p "$logs"

[[ $# -gt 0 ]] || set -- "$PWD"
status=0
for dir in "$@"; do
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || (cd "$dir" && pwd))
  if [[ ! -f $root/pom.xml ]]; then
    echo "forge: $root has no pom.xml, skipped" >&2
    continue
  fi
  log="$logs/$(basename "$root").log"
  echo "forge: $root"
  if ! (cd "$root" && "${mvn[@]}" "$plugin" -DdownloadSources) >"$log" 2>&1; then
    grep -E '^\[ERROR\]' "$log" >&2 || true
    echo "forge: $root: Maven failed; full log: $log" >&2
    status=1
    continue
  fi
  # A library that publishes no sources jar is a warning, not a failure.
  missing=$(grep -o '[^ :]*:[^ :]*:jar:sources:[^ ]* (absent)' "$log" | sort -u | cut -d: -f1,2)
  if [[ -n $missing ]]; then
    echo "forge: $root: no sources published for $(wc -l <<<"$missing" | tr -d ' ') libraries:"
    sed 's/^/  /' <<<"$missing"
  else
    echo "forge: $root: sources for every dependency"
  fi
done
exit "$status"
