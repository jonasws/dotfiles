#!/usr/bin/env bash
# The sandboxed half of probe.sh; it runs this inside nono. Prints one line per
# check: RESULT<TAB>ID<TAB>label<TAB>detail, RESULT being PASS, FAIL or SKIP.
#
# Usage: probe-inside.sh PROBE_REPO TAG
set -u
repo=$1
tag=$2

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}"; }
last_line() { local s=${1%$'\n'}; printf '%s' "${s##*$'\n'}"; }

# denied ID LABEL -- COMMAND...: passes when the command fails.
denied() {
  local id=$1 label=$2 out
  shift 3
  if out=$("$@" 2>&1); then
    emit FAIL "$id" "$label" "allowed: $*"
  else
    emit PASS "$id" "$label" "$(last_line "$out")"
  fi
}

# allowed ID LABEL -- COMMAND...: passes when the command succeeds.
allowed() {
  local id=$1 label=$2 out
  shift 3
  if out=$("$@" 2>&1); then
    emit PASS "$id" "$label"
  else
    emit FAIL "$id" "$label" "$(last_line "$out")"
  fi
}

# S1: files that run outside the sandbox without asking are read-only.
denied S1 'repo .git/hooks' -- touch "$repo/.git/hooks/nono-probe"
denied S1 'repo .git/config' -- git -C "$repo" config --local nono.probe 1
denied S1 'repo .mcp.json' -- touch "$repo/.mcp.json"
denied S1 'repo .claude/settings.json' -- touch "$repo/.claude/settings.json"
denied S1 'repo mise.local.toml' -- touch "$repo/mise.local.toml"
denied S1 '~/.claude/settings.json' -- touch "$HOME/.claude/settings.json"
denied S1 '~/.claude/hooks' -- mkdir -p "$HOME/.claude/hooks/nono-probe-$tag"

# S8: instructions and extensions every later session loads are read-only.
denied S8 '~/.claude/CLAUDE.md' -- touch "$HOME/.claude/CLAUDE.md"
denied S8 '~/.claude/skills' -- mkdir -p "$HOME/.claude/skills/nono-probe-$tag"
denied S8 '~/.claude/agents' -- mkdir -p "$HOME/.claude/agents/nono-probe-$tag"
denied S8 '~/.claude/commands' -- mkdir -p "$HOME/.claude/commands/nono-probe-$tag"
denied S8 '~/.claude/output-styles' -- mkdir -p "$HOME/.claude/output-styles/nono-probe-$tag"
if [[ -d $HOME/.pi/agent ]]; then
  denied S8 '~/.pi/agent/extensions' -- mkdir -p "$HOME/.pi/agent/extensions/nono-probe-$tag"
  denied S8 '~/.pi/agent/AGENTS.md' -- touch "$HOME/.pi/agent/AGENTS.md"
else
  emit SKIP S8 '~/.pi/agent' 'pi is not set up here'
fi
allowed S8 "Claude Code's own state still writes" -- touch "$HOME/.claude/.nono-probe-$tag"

# S9: secrets in repo .env files are unreadable; examples stay readable.
denied S9 'repo .env' -- cat "$repo/.env"
denied S9 'nested .env.local' -- cat "$repo/sub/.env.local"
allowed S9 '.env.example' -- cat "$repo/.env.example"
allowed S9 '.env still visible to ls' -- test -e "$repo/.env"

# S2, S3: ordinary git work still writes, and commits come out signed.
allowed S2 'commit in a workspace repo' -- git -C "$repo" commit -q --allow-empty -m 'nono probe'
scratch=${XDG_CACHE_HOME:-$HOME/.cache}/nono-probe-$tag
allowed S2 'scratch repo config writes' -- bash -c 'git init -q "$1" && git -C "$1" config --local nono.probe 1' _ "$scratch"
if git -C "$repo" cat-file commit HEAD 2>/dev/null | grep -q '^gpgsig '; then
  emit PASS S3 'agent commit is signed'
else
  emit FAIL S3 'agent commit is signed' "$(git -C "$repo" config --get gpg.format) / $(git -C "$repo" config --get user.signingkey)"
fi

# S4: ssh remotes are rewritten to https.
allowed S4 'ssh remote fetches over https' -- git ls-remote git@github.com:git/git.git HEAD

# S5: launchd cannot start work outside the sandbox. probe.sh checks the file.
if command -v launchctl >/dev/null; then
  denied S5 'launchctl submit refused' -- launchctl submit -l "nono.probe.$tag" -- /usr/bin/touch "/tmp/nono-escaped-$tag"
else
  emit SKIP S5 'launchctl submit refused' 'no launchctl here'
fi

# S7, E4: an allowed docs host works; Exa is reachable only through the gate.
allowed S7 'code.claude.com reachable' -- curl -fsS -o /dev/null --max-time 20 https://code.claude.com/docs/en/settings
# Any HTTP status, even 401 or 404, means Exa answered; nono refuses the tunnel.
if code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 https://api.exa.ai/search 2>/dev/null); then
  emit FAIL E4 'api.exa.ai refused' "Exa answered with HTTP $code"
else
  emit PASS E4 'api.exa.ai refused'
fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST http://127.0.0.1:47811/answer 2>/dev/null)
if [[ $code == 403 ]]; then
  emit PASS E1 'Exa gate reachable from the sandbox'
else
  emit FAIL E1 'Exa gate reachable from the sandbox' "got $code, expected 403"
fi

# D6: the Context7 cache and its markdown copy land in the agents' cache.
c7=$HOME/.claude/skills/find-docs/context7.sh
if [[ -z ${CONTEXT7_API_KEY:-} ]]; then
  emit SKIP D6 'Context7 cache in the sandbox' 'CONTEXT7_API_KEY is not set inside nono'
elif out=$(bash "$c7" context libraryId=/jdx/mise 'query=How do I define a task with dependencies?' 2>&1 >/dev/null); then
  start=$SECONDS
  bash "$c7" context 'query=How do I define a task with dependencies?' libraryId=/jdx/mise >/dev/null 2>&1
  dir=${XDG_CACHE_HOME:-$HOME/.cache}/context7
  if compgen -G "$dir/*.json" >/dev/null && compgen -G "$dir/docs/jdx/mise/*.md" >/dev/null && (( SECONDS - start < 2 )); then
    emit PASS D6 'Context7 cache in the sandbox' "$dir"
  else
    emit FAIL D6 'Context7 cache in the sandbox' "no entry or markdown copy under $dir, or the repeat call was slow"
  fi
else
  emit FAIL D6 'Context7 cache in the sandbox' "$(last_line "$out")"
fi

# H1, H2: the shell Claude Code is pinned to, and the first bash on PATH.
for id in H1 H2; do
  if [[ $id == H1 ]]; then bin=/opt/homebrew/bin/bash label='CLAUDE_CODE_SHELL target is bash 4+'
  else bin=$(command -v bash) label="first bash on PATH is 4+"
  fi
  version=$("$bin" -c 'echo "${BASH_VERSINFO[0]}"' 2>&1)
  if [[ $version =~ ^[0-9]+$ ]] && (( version >= 4 )); then
    emit PASS "$id" "$label" "$bin"
  else
    emit FAIL "$id" "$label" "$bin: $version"
  fi
done
