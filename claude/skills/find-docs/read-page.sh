#!/usr/bin/env bash
# Read a web page as markdown: the server's own markdown or plain text when it
# has one, otherwise its HTML converted by defuddle.
#
# Usage: read-page.sh [-o <file>] <url>
#
# With -o the markdown goes to <file> and one line saying so to stdout. Without
# it, on a terminal the page opens in leaf; otherwise the markdown goes to
# stdout, so `read-page.sh <url> > page.md` also gives a file to grep. Nothing reaches stdout
# or leaf unless a page came back: on failure the reason goes to stderr and the
# exit status is 1. A conversion is announced on stderr, because an extraction
# can drop what the page itself had. One request per page: defuddle converts the
# body that request returned.
set -euo pipefail

# Homebrew's curl: macOS's /usr/bin/curl (LibreSSL, older) comes first on a
# PATH that fish or bash did not set up, as under launchd. CURL overrides.
curl_bin=${CURL:-${HOMEBREW_PREFIX:-/opt/homebrew}/opt/curl/bin/curl}
[[ -x $curl_bin ]] || { echo "$(basename "$0"): no Homebrew curl at $curl_bin; run 'brew install curl'" >&2; exit 1; }
curl() { command "$curl_bin" "$@"; }

out=
if [[ ${1:-} == -o ]]; then
  out=${2:?usage: read-page.sh [-o <file>] <url>}
  shift 2
fi
url=${1:?usage: read-page.sh [-o <file>] <url>}
page=$(mktemp "${TMPDIR:-/tmp}/read-page.XXXXXX")
json=$(mktemp "${TMPDIR:-/tmp}/read-page.XXXXXX")
trap 'rm -f "$page" "$json" "$json".*' EXIT

# github.com serves HTML whatever the Accept header says, and the agent sandbox
# lets only git traffic reach it. Its API holds the same pages as markdown: a
# README as its own bytes, issues, PRs and releases as JSON whose bodies are
# markdown. github.sh carries the token, so these count against its rate limit.
github=$(dirname "${BASH_SOURCE[0]}")/github.sh

# issue_markdown <issue.json> <comments.json> renders an issue or PR thread.
issue_markdown() {
  jq -r --slurpfile comments "$2" '
    def who: .user.login // "ghost";
    "# \(.title) (#\(.number))",
    "",
    ([(if .pull_request then "pull request" else "issue" end),
      (if .pull_request.merged_at then "merged \(.pull_request.merged_at[:10])" else .state end),
      "opened by \(who) on \(.created_at[:10])"] | join(", ")),
    (if (.labels | length) > 0 then "Labels: \([.labels[].name] | join(", "))" else empty end),
    .html_url,
    "",
    (.body // "_No description._"),
    (if ($comments[0] | length) > 0 then
      "", "## Comments (\($comments[0] | length) of \(.comments))",
      ($comments[0][] | "", "### \(who), \(.created_at[:10])", "", .body)
    else empty end)
  ' "$1"
}

release_markdown() { # <release.json or list.json>
  jq -r '
    (if type == "array" then .[] else . end)
    | "# \(.name // .tag_name)", "",
      "Tag \(.tag_name), published \((.published_at // .created_at)[:10])\(if .prerelease then ", prerelease" else "" end)",
      .html_url, "", (.body // "_No release notes._"), ""
  ' "$1"
}

# github_page writes $page from the API and returns 0, or returns 1 for a
# github.com URL it has no API route for, and for every other URL.
github_page() {
  local path=${url%%[?#]*}
  path=${path%/}
  [[ $path =~ ^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(/.*)?$ ]] || return 1
  local repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}" rest=${BASH_REMATCH[3]}
  case $rest in
    '')
      # A two-part path can be a site page (github.com/features/copilot), not a
    # repository; its 404 is expected, and the page fetch below reports.
    "$github" api -o "$page" --raw "repos/$repo/readme" 2>/dev/null || return 1
      echo "read-page: $url is a repository; reading its README through the GitHub API" >&2
      ;;
    /blob/*)
      # The contents API wants ref and path apart, which a ref with a slash
      # makes ambiguous; raw.githubusercontent.com resolves that itself.
      url="https://raw.githubusercontent.com/$repo/${rest#/blob/}"
      echo "read-page: reading the raw file at $url" >&2
      return 1
      ;;
    /issues/[0-9]* | /pull/[0-9]*)
      local n=${rest#/*/}
      n=${n%%/*}
      [[ $n =~ ^[0-9]+$ ]] || return 1
      "$github" api -o "$json" "repos/$repo/issues/$n" || return 1
      local total pages p
      total=$(jq '.comments' "$json")
      pages=$(( (total + 99) / 100 ))
      (( pages > 10 )) && pages=10
      for (( p = 1; p <= pages; p++ )); do
        "$github" api -o "$json.$p" "repos/$repo/issues/$n/comments?per_page=100&page=$p" || return 1
      done
      if (( pages > 0 )); then jq -s 'add' "$json".[0-9]* >"$json.all"; else echo '[]' >"$json.all"; fi
      issue_markdown "$json" "$json.all" >"$page"
      echo "read-page: read #$n of $repo through the GitHub API (body and comments, no review comments)" >&2
      ;;
    /releases | /releases/latest | /releases/tag/*)
      local api=releases?per_page=30
      [[ $rest == /releases/latest ]] && api=releases/latest
      [[ $rest == /releases/tag/* ]] && api=releases/tags/${rest#/releases/tag/}
      "$github" api -o "$json" "repos/$repo/$api" || return 1
      release_markdown "$json" >"$page"
      echo "read-page: read the releases of $repo through the GitHub API" >&2
      ;;
    *) return 1 ;;
  esac
}

if ! github_page; then
  # One request that prefers markdown and accepts HTML, so a server with both
  # picks markdown and one with only HTML still answers 2xx.
  reply=$(curl -sSL --max-time 30 \
    -H 'Accept: text/markdown, text/x-markdown;q=0.95, text/html;q=0.9, application/xhtml+xml;q=0.9, text/plain;q=0.8' \
    -o "$page" -w '%{http_code}\t%{content_type}\t%{url_effective}' "$url") || exit 1
  IFS=$'\t' read -r code type final <<<"$reply"

  if [[ $code != 2?? ]]; then
    echo "read-page: $url answered $code" >&2
    if [[ $code == 403 && $url == https://github.com/* ]]; then
      echo "read-page: the agent sandbox lets only git traffic reach github.com, and read-page has no API route for this page; use github.sh api, search or clone" >&2
    fi
    exit 1
  fi

  case "$type" in
    # Plain text such as llms.txt is already readable as markdown.
    text/markdown* | text/x-markdown* | text/plain*) ;;
    text/html* | application/xhtml+xml*)
      echo "read-page: $url has no markdown version; converting its HTML with defuddle" >&2
      # defuddle reads the body already fetched instead of fetching again. A
      # <base> tag stands in for the URL it would otherwise have, so relative
      # links still resolve; a page's own <base> comes first and wins.
      perl -0pi -e '
        BEGIN { $b = shift } next if /<base\s/i;
        s/(<head\b[^>]*>)/$1<base href="$b">/i or $_ = qq(<base href="$b">) . $_;
      ' "$final" "$page"
      converted=$(defuddle parse - --md <"$page") || exit 1
      printf '%s\n' "$converted" >"$page"
      ;;
    *)
      echo "read-page: $url answered ${type:-without a content type}, which is neither markdown nor HTML" >&2
      exit 1
      ;;
  esac
fi

if [[ ! -s $page ]]; then
  echo "read-page: $url produced no content" >&2
  exit 1
fi

if [[ -n $out ]]; then
  cp "$page" "$out"
  echo "read-page: wrote $(wc -c <"$out" | tr -d ' ') bytes to $out"
elif [[ -t 1 ]]; then
  leaf <"$page"
else
  cat "$page"
fi
