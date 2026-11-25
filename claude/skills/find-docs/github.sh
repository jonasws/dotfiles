#!/usr/bin/env bash
# Public GitHub repositories, read-only: the source, issues, PRs, releases and
# commits of open-source projects, with no MCP server and no gh.
#
#   github.sh clone  -o <dir>  <owner>/<repo> [<ref>]   shallow, blobless clone; prints <dir>
#   github.sh api    -o <file> [--raw] <path>           GET https://api.github.com/<path>
#                                                       --raw: a file or README's own bytes
#   github.sh search -o <file> issues|code|commits|repositories <query>
#
# Output goes to a file or directory, never the conversation: grep it after.
# The API calls send $GITHUB_PERSONAL_ACCESS_TOKEN when it is set. Inside the
# agent sandbox that is a placeholder that nono swaps for a public-read token;
# elsewhere it is usually unset, and GitHub's anonymous limit (60 an hour,
# none for code search) applies.
set -euo pipefail

# Homebrew's curl: macOS's /usr/bin/curl (LibreSSL, older) comes first on a
# PATH that fish or bash did not set up, as under launchd. CURL overrides.
curl_bin=${CURL:-${HOMEBREW_PREFIX:-/opt/homebrew}/opt/curl/bin/curl}
[[ -x $curl_bin ]] || { echo "$(basename "$0"): no Homebrew curl at $curl_bin; run 'brew install curl'" >&2; exit 1; }
curl() { command "$curl_bin" "$@"; }

die() { echo "github.sh: $*" >&2; exit 2; }

api_get() { # <url> <file> [<media type>]
  local auth=() accept=${3:-application/vnd.github+json}
  [[ -n ${GITHUB_PERSONAL_ACCESS_TOKEN:-} ]] && auth=(-H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN")
  # --fail-with-body keeps GitHub's JSON reason (a 422 names the bad query);
  # it goes to stderr, and the output file is left out.
  if ! curl -sS --fail-with-body --max-time 30 -H "Accept: $accept" \
    -H 'X-GitHub-Api-Version: 2022-11-28' "${auth[@]}" -o "$2.part" "$1"; then
    [[ -s $2.part ]] && cat "$2.part" >&2
    rm -f "$2.part"
    die "GET $1 failed"
  fi
  mv "$2.part" "$2"
}

cmd=${1:-}
[[ ${2:-} == -o && -n ${3:-} ]] || die "usage: github.sh clone|api|search -o <out> ..."
out=$3
shift 3

case $cmd in
clone)
  repo=${1:?owner/repo}
  ref=${2:-}
  [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "not owner/repo: $repo"
  if [[ -d $out/.git ]]; then
    git -C "$out" fetch -q --depth 1 --filter=blob:none origin "${ref:-HEAD}"
    git -C "$out" checkout -q FETCH_HEAD
  else
    git clone -q --depth 1 --filter=blob:none ${ref:+--branch "$ref"} \
      "https://github.com/$repo.git" "$out"
  fi
  echo "$out"
  ;;
api)
  accept=
  if [[ ${1:-} == --raw ]]; then
    accept=application/vnd.github.raw
    shift
  fi
  path=${1:?path}
  [[ $path != *://* ]] || die "give the path after api.github.com/, not a URL"
  api_get "https://api.github.com/${path#/}" "$out" ${accept:+"$accept"}
  ;;
search)
  kind=${1:?issues|code|commits|repositories}
  query=${2:?query}
  [[ $kind =~ ^(issues|code|commits|repositories)$ ]] || die "search kind: $kind"
  # GitHub answers 422 to an issues search that names neither kind.
  if [[ $kind == issues && ! $query =~ (^|[[:space:]])(is|type):(issue|pr|pull-request)($|[[:space:]]) ]]; then
    die "search issues needs is:issue or is:pr in the query"
  fi
  q=$(jq -rn --arg q "$query" '$q|@uri')
  api_get "https://api.github.com/search/$kind?q=$q&per_page=50" "$out"
  ;;
*) die "unknown command: $cmd" ;;
esac
