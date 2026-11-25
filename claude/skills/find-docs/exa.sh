#!/usr/bin/env bash
# Query Exa's REST API: web search, and page contents by URL.
#
# Usage: exa.sh search <query> [-o <file>] [--json] [options]
#        exa.sh contents <url>... [-o <file>] [--json] [--text N]
#
#   search options:
#     -n N              results (default 8, max 100)
#     --text N          each result's page text, up to N characters
#     --full            each result's full page text
#     --domain D        only this domain; repeat for more
#     --exclude D       never this domain; repeat for more
#     --since DATE      published on or after DATE (YYYY-MM-DD)
#     --category C      company, research paper, news, pdf, github, personal site,
#                       people, financial report
#   Without --text or --full, each result carries highlights (about 1500 chars).
#
#   contents --text N   cap each page at N characters (default: the whole page)
#
# Output is markdown, one section per result; --json prints Exa's JSON. With -o
# it goes to <file> and one line saying so goes to stdout. -o and --json go
# anywhere on the line.
#
# Requests go to EXA_API_BASE_URL, by default the exa-gate on 127.0.0.1:47811,
# which holds the key and serves page contents from Exa's cache only: a URL
# Exa has not crawled is fetched only after a yes in the tuios pane. Pointing
# EXA_API_BASE_URL at https://api.exa.ai with EXA_API_KEY set skips the gate.
#
# Answers are cached on disk for EXA_CACHE_HOURS (default 24), keyed by
# endpoint and request body. EXA_CACHE_HOURS=0 skips the cache read.
#
# Exit status: 0 on success, 1 on a failed request, 2 on bad usage, 3 when
# some URLs of a contents call came back without a page (not cached and not
# allowed, or unreachable); the pages that did come back are still printed.
set -euo pipefail

# Homebrew's curl: macOS's /usr/bin/curl (LibreSSL, older) comes first on a
# PATH that fish or bash did not set up, as under launchd. CURL overrides.
curl_bin=${CURL:-${HOMEBREW_PREFIX:-/opt/homebrew}/opt/curl/bin/curl}
[[ -x $curl_bin ]] || { echo "$(basename "$0"): no Homebrew curl at $curl_bin; run 'brew install curl'" >&2; exit 1; }
curl() { command "$curl_bin" "$@"; }

usage() {
  sed -n '4,5p' "${BASH_SOURCE[0]}" | sed 's/^# *//' >&2
  exit 2
}

out= raw=false
while [[ ${1:-} == -* ]]; do
  case $1 in
    -o) out=${2:?-o needs a file}; shift 2 ;;
    --json) raw=true; shift ;;
    *) break ;;
  esac
done
kind=${1:-}
[[ $kind == search || $kind == contents ]] || usage
shift

base=${EXA_API_BASE_URL:-http://127.0.0.1:47811}
key=${EXA_API_KEY:-via-exa-gate}

if [[ $kind == search ]]; then
  query=${1:-}
  [[ -n $query && $query != -* ]] || usage
  shift
  n=8 text= full=false since= category=
  domains=() excludes=()
  while (( $# )); do
    case $1 in
      -n) n=$2; shift 2 ;;
      --text) text=$2; shift 2 ;;
      --full) full=true; shift ;;
      --domain) domains+=("$2"); shift 2 ;;
      --exclude) excludes+=("$2"); shift 2 ;;
      --since) since=$2; shift 2 ;;
      --category) category=$2; shift 2 ;;
      -o) out=$2; shift 2 ;;
      --json) raw=true; shift ;;
      *) echo "exa: unknown search option '$1'" >&2; usage ;;
    esac
  done
  [[ $n =~ ^[0-9]+$ ]] || { echo "exa: -n takes a number" >&2; exit 2; }
  [[ -z $text || $text =~ ^[0-9]+$ ]] || { echo "exa: --text takes a number" >&2; exit 2; }
  body=$(jq -n --arg q "$query" --argjson n "$n" --arg text "$text" --argjson full "$full" \
    --arg since "$since" --arg category "$category" \
    '{query: $q, numResults: $n, type: "auto",
      contents: (if $full then {text: true}
                 elif $text != "" then {text: {maxCharacters: ($text | tonumber)}}
                 else {highlights: {maxCharacters: 1500}} end)}
     + (if $since != "" then {startPublishedDate: $since} else {} end)
     + (if $category != "" then {category: $category} else {} end)')
  if (( ${#domains[@]} )); then body=$(jq '.includeDomains = $ARGS.positional' --args "${domains[@]}" <<<"$body"); fi
  if (( ${#excludes[@]} )); then body=$(jq '.excludeDomains = $ARGS.positional' --args "${excludes[@]}" <<<"$body"); fi
  endpoint=search
else
  text=
  urls=()
  while (( $# )); do
    case $1 in
      --text) text=$2; shift 2 ;;
      -o) out=$2; shift 2 ;;
      --json) raw=true; shift ;;
      -*) echo "exa: unknown contents option '$1'" >&2; usage ;;
      *) urls+=("$1"); shift ;;
    esac
  done
  (( ${#urls[@]} )) || usage
  body=$(jq -n --arg text "$text" '{urls: $ARGS.positional,
    text: (if $text != "" then {maxCharacters: ($text | tonumber)} else true end)}' --args "${urls[@]}")
  endpoint=contents
fi

ttl_hours=${EXA_CACHE_HOURS:-24}
[[ $ttl_hours =~ ^[0-9]+$ ]] || { echo "exa: EXA_CACHE_HOURS must be whole hours" >&2; exit 2; }
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/exa
digest() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -c1-32; }
cached=$cache_dir/$({ echo "$endpoint"; jq -cS . <<<"$body"; } | digest).json

if ! (( ttl_hours > 0 )) || [[ ! -s $cached || -z $(find "$cached" -mmin "-$((ttl_hours * 60))") ]]; then
  rc=0
  response=$(curl -sS --fail-with-body --max-time 180 -X POST "$base/$endpoint" \
    -H 'Content-Type: application/json' -H "x-api-key: $key" --data-binary "$body") || rc=$?
  if (( rc != 0 )); then
    [[ -n $response ]] && printf '%s\n' "$response" >&2
    echo "exa: $endpoint request to $base failed (curl exit $rc)" >&2
    exit 1
  fi
  mkdir -p "$cache_dir"
  printf '%s\n' "$response" >"$cached.part"
  # A contents answer with missing pages stays out of the cache, so a later
  # call asks again once Exa has the page or you allow the fetch.
  if jq -e '[.statuses[]? | select(.status == "error")] | length > 0' "$cached.part" >/dev/null; then
    mv "$cached.part" "$cached.miss"
    cached=$cached.miss
  else
    mv "$cached.part" "$cached"
  fi
fi

render() {
  if [[ $raw == true ]]; then
    jq . "$cached"
  else
    jq -r '
      (.results // [])[] |
      "## \(if (.title // "") == "" then .url else .title end)\n\(.url)" +
      (if .publishedDate then "\npublished: \(.publishedDate[0:10])" else "" end) +
      (if (.author // "") != "" then "  author: \(.author)" else "" end) + "\n\n" +
      (if .text then .text
       elif .highlights then (.highlights | join("\n\n…\n\n"))
       else "" end) + "\n"' "$cached"
  fi
}

if [[ -n $out ]]; then
  render >"$out"
  echo "exa: wrote $(wc -c <"$out" | tr -d ' ') bytes to $out"
else
  render
fi

missing=$(jq -r '.statuses[]? | select(.status == "error") | "\(.id) (\(.error.tag // "error"))"' "$cached")
if [[ -n $missing ]]; then
  while IFS= read -r line; do echo "exa: no page for $line" >&2; done <<<"$missing"
  gate=$(jq -r '.gate // empty' "$cached")
  if [[ -n $gate ]]; then echo "exa: $gate" >&2; fi
  exit 3
fi
