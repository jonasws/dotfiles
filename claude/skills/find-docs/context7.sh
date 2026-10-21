#!/usr/bin/env bash
# Query the Context7 API: one of its three GET endpoints, with each further
# argument sent as one url-encoded parameter.
#
# Usage: context7.sh search|libs|context <name>=<value>...
#
#   context7.sh search 'query=How do I write a server filter in http4k?' language=Kotlin
#   context7.sh libs libraryName=http4k 'query=server filters'
#   context7.sh context libraryId=/http4k/api 'query=How do I write a server filter?'
#
# `libs` prints the top five candidates as TSV: id, title, totalSnippets,
# trustScore, benchmarkScore, and up to five indexed versions. The key comes
# from CONTEXT7_API_KEY, which a SessionStart hook (claude/hooks/context7-env.sh)
# puts into every Bash command of a session.
#
# -sS drops the progress meter but still prints a one-line reason when the
# connection fails (plain -s exits 6 silently, which reads like an empty
# result). --fail-with-body exits non-zero on an HTTP error while keeping
# Context7's one-line JSON reason.
set -euo pipefail

usage='usage: context7.sh search|libs|context <name>=<value>...'
case "${1:-}" in
  search) endpoint=v3/search ;;
  libs) endpoint=v2/libs/search ;;
  context) endpoint=v2/context ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
kind=$1
shift

if [[ -z ${CONTEXT7_API_KEY:-} ]]; then
  echo 'context7: CONTEXT7_API_KEY is empty; the SessionStart hook did not resolve it' >&2
  exit 1
fi

params=()
for arg in "$@"; do
  [[ $arg == *=* ]] || { echo "context7: '$arg' is not <name>=<value>; $usage" >&2; exit 2; }
  params+=(--data-urlencode "$arg")
done

request() {
  curl -sSG --fail-with-body --max-time 30 "https://context7.com/api/$endpoint" \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" "${params[@]}"
}

if [[ $kind == libs ]]; then
  request | jq -r '.results[:5][] | [.id, .title, .totalSnippets, .trustScore, .benchmarkScore, ((.versions // [])[:5] | join(","))] | @tsv'
else
  request
fi
