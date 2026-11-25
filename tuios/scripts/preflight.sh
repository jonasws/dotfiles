#!/usr/bin/env bash
# Pre-push check for a Kotlin/Maven service repo under ~/CX, ~/CNOPS or
# ~/CN-TERMINAL, run from its main checkout:
#
#   git     the default branch is checked out, clean, and level with origin
#   verify  mvn clean verify passes; the output goes to a log, not the screen
#   docker  the service image builds; it is removed again, pass or fail
#
# Each stage ends on one line, "preflight <stage>: ok" or "preflight <stage>:
# FAIL", which tuios/tapes/preflight.tape waits on. The first failure stops the
# run. The docker stage copies target/app.jar, so on its own it needs an
# earlier verify.
#
# Usage: preflight.sh [git|verify|docker|all]    (default: all)

set -uo pipefail

stage=${1:-all}
case $stage in git | verify | docker | all) ;; *)
  echo "usage: ${0##*/} [git|verify|docker|all]" >&2
  exit 2
  ;;
esac

mark() { printf 'preflight %s: %s%s\n' "$1" "$2" "${3:+ - $3}"; }
fail() {
  mark "$1" FAIL "$2"
  exit 1
}

root=$(git rev-parse --show-toplevel 2>/dev/null) || fail git "not inside a git repository"
cd "$root" || fail git "cannot cd to $root"
repo=${root##*/}
logs=${XDG_STATE_HOME:-$HOME/.local/state}/preflight
mkdir -p "$logs" || fail "$stage" "cannot create $logs"
stamp=$(date +%Y%m%d-%H%M%S)
summary=()

check_git() {
  git fetch --quiet origin || fail git "git fetch origin failed"
  local upstream
  upstream=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD) ||
    { git remote set-head origin --auto >/dev/null 2>&1 &&
      upstream=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD); } ||
    fail git "origin/HEAD is not set and could not be detected"
  local branch=${upstream#origin/} current
  current=$(git branch --show-current)
  [[ $current == "$branch" ]] || fail git "on '${current:-detached HEAD}', not the default branch $branch"

  local dirty
  dirty=$(git status --porcelain)
  if [[ -n $dirty ]]; then
    git status --short | head -n 15
    fail git "$(wc -l <<<"$dirty" | tr -d ' ') uncommitted or untracked path(s)"
  fi

  local behind ahead
  read -r behind ahead < <(git rev-list --left-right --count "$upstream...HEAD")
  ((behind == 0)) || fail git "$branch is $behind commit(s) behind $upstream: pull first"
  # Ahead is the normal state before a push (a local `tuios ship merge` leaves
  # it there), so it is reported, not failed.
  if ((ahead > 0)); then
    mark git ok "$branch at $(git rev-parse --short HEAD), $ahead commit(s) ahead of $upstream, none behind"
    summary+=("$branch $ahead ahead of origin, none behind")
  else
    mark git ok "$branch at $(git rev-parse --short HEAD), level with $upstream"
    summary+=("$branch level with origin")
  fi
}

# Totals of the per-module "Results:" lines, which have no "Time elapsed".
test_totals() {
  awk '/^\[(INFO|WARNING|ERROR)\] Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+$/ {
         gsub(/,/, ""); run += $4; failed += $6 + $8; skipped += $10 }
       END { if (run) printf "%d tests, %d failed, %d skipped", run, failed, skipped }' "$1"
}

check_verify() {
  local log=$logs/$repo-$stamp-verify.log
  echo "mvn clean verify -> $log"
  if mvn -B clean verify >"$log" 2>&1; then
    local totals
    totals=$(test_totals "$log")
    mark verify ok "${totals:-no test results found}; log $log"
    summary+=("verify ${totals:-passed}")
  else
    tail -n 40 "$log"
    fail verify "mvn clean verify failed; log $log"
  fi
}

check_docker() {
  # Testcontainers and this check share the colima socket; an interactive
  # shell gets DOCKER_HOST from the repo's .mise.local.toml.
  local colima=$HOME/.config/colima/default/docker.sock
  if [[ -z ${DOCKER_HOST:-} && -S $colima ]]; then
    export DOCKER_HOST=unix://$colima
  fi
  docker info >/dev/null 2>&1 ||
    fail docker "no Docker daemon at ${DOCKER_HOST:-the default socket}: colima start"
  [[ -f Dockerfile ]] || fail docker "no Dockerfile in $root"

  local log=$logs/$repo-$stamp-docker.log
  # Global, not local: the EXIT trap reads it after this function has returned.
  tag=preflight-$repo:$(git rev-parse --short HEAD)
  trap 'docker rmi --force "$tag" >/dev/null 2>&1' EXIT
  echo "docker build -t $tag -> $log"
  if docker build -t "$tag" . >"$log" 2>&1; then
    trap - EXIT
    docker rmi "$tag" >/dev/null 2>&1 || echo "could not remove $tag; docker rmi $tag"
    mark docker ok "$tag built and removed; log $log"
    summary+=("image built and removed")
  else
    tail -n 30 "$log"
    fail docker "docker build failed (a DNS error usually means colima restart); log $log"
  fi
}

case $stage in
  git) check_git ;;
  verify) check_verify ;;
  docker) check_docker ;;
  all) check_git && check_verify && check_docker ;;
esac

if [[ $stage == all ]]; then
  printf -v joined '%s, ' "${summary[@]}"
  printf 'preflight: all passed - %s: %s\n' "$repo" "${joined%, }"
fi
exit 0
