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
# from CONTEXT7_API_KEY in the environment.
#
# Answers are cached on disk for CONTEXT7_CACHE_HOURS (default 72), keyed by
# endpoint and parameters in any order, so agents asking the same question
# share one call. Context7 sends no ETag and `max-age=0`, so there is nothing
# to revalidate against, and a conditional request would cost a call anyway.
# CONTEXT7_CACHE_HOURS=0 skips the cache read and stores the fresh answer.
# Each `context` answer is also written as markdown under docs/<libraryId>/,
# with the library, query and fetch time in frontmatter, for the
# `forge:docs-index` task to index with qmd.
# When Context7 is unreachable, rate-limited or failing, an expired answer is
# served instead, with a note on stderr.
#
# -sS drops the progress meter but still prints a one-line reason when the
# connection fails. --fail-with-body exits non-zero on an HTTP error while
# keeping Context7's one-line JSON reason.
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
  echo 'context7: CONTEXT7_API_KEY is empty; the key is missing from the environment' >&2
  exit 1
fi

params=()
for arg in "$@"; do
  [[ $arg == *=* ]] || { echo "context7: '$arg' is not <name>=<value>; $usage" >&2; exit 2; }
  params+=(--data-urlencode "$arg")
done

ttl_hours=${CONTEXT7_CACHE_HOURS:-72}
[[ $ttl_hours =~ ^[0-9]+$ ]] || { echo "context7: CONTEXT7_CACHE_HOURS must be whole hours" >&2; exit 2; }
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/context7

digest() {
  if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -c1-32
}
key=$({ echo "$endpoint"; printf '%s\n' "$@" | LC_ALL=C sort; } | digest)
cached=$cache_dir/$key.json

# param NAME ARGS... prints the value of the first NAME=value in ARGS.
param() {
  local name=$1 arg
  shift
  for arg in "$@"; do [[ $arg == "$name="* ]] && { printf '%s' "${arg#*=}"; return; }; done
  return 0
}

write_markdown() {
  local library query dir
  library=$(param libraryId "$@")
  query=$(param query "$@")
  [[ -n $library ]] || return 0
  dir=$cache_dir/docs/$(printf '%s' "${library#/}" | tr -c 'A-Za-z0-9._/-' '_')
  mkdir -p "$dir"
  {
    echo '---'
    echo 'source: context7'
    printf 'library: %s\n' "$(jq -n --arg v "$library" '$v')"
    printf 'query: %s\n' "$(jq -n --arg v "$query" '$v')"
    printf 'fetched: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo '---'
    echo
    printf '# %s\n\n' "${query:-$library}"
    if [[ ${body:0:1} == '{' || ${body:0:1} == '[' ]]; then
      printf '```json\n%s\n```\n' "$body"
    else
      printf '%s\n' "$body"
    fi
  } >"$dir/$key.md.part"
  mv "$dir/$key.md.part" "$dir/$key.md"
}

emit() {
  if [[ $kind == libs ]]; then
    jq -r '.results[:5][] | [.id, .title, .totalSnippets, .trustScore, .benchmarkScore, ((.versions // [])[:5] | join(","))] | @tsv' "$1"
  else
    cat "$1"
  fi
}

if (( ttl_hours > 0 )) && [[ -s $cached && -n $(find "$cached" -mmin "-$((ttl_hours * 60))") ]]; then
  emit "$cached"
  exit 0
fi

rc=0
out=$(curl -sSG --fail-with-body --max-time 30 "https://context7.com/api/$endpoint" \
  -H "Authorization: Bearer $CONTEXT7_API_KEY" "${params[@]}" \
  -w '\n%{http_code}|%header{ratelimit-remaining}|%header{retry-after}') || rc=$?
meta=${out##*$'\n'}
body=${out%$'\n'*}
IFS='|' read -r code remaining retry_after <<<"$meta" || true

if (( rc == 0 )); then
  mkdir -p "$cache_dir"
  printf '%s\n' "$body" >"$cached.part"
  mv "$cached.part" "$cached"
  if [[ $kind == context ]]; then
    write_markdown "$@" || echo "context7: could not write the markdown copy for qmd" >&2
  fi
  if [[ ${remaining:-} =~ ^[0-9]+$ ]] && (( remaining < 20 )); then
    echo "context7: $remaining requests left in this rate-limit window" >&2
  fi
  emit "$cached"
  exit 0
fi

if [[ -s $cached && $code =~ ^(000|429|5..)$ ]]; then
  echo "context7: request failed (HTTP $code); this answer is from an expired cache entry" >&2
  emit "$cached"
  exit 0
fi

[[ -n $body ]] && printf '%s\n' "$body"
if [[ $code == 429 && -n ${retry_after:-} ]]; then
  echo "context7: rate-limited; retry after ${retry_after}s" >&2
fi
exit "$rc"
