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

out=
if [[ ${1:-} == -o ]]; then
  out=${2:?usage: read-page.sh [-o <file>] <url>}
  shift 2
fi
url=${1:?usage: read-page.sh [-o <file>] <url>}
page=$(mktemp "${TMPDIR:-/tmp}/read-page.XXXXXX")
trap 'rm -f "$page"' EXIT

# One request that prefers markdown and accepts HTML, so a server with both
# picks markdown and one with only HTML still answers 2xx.
reply=$(curl -sSL --max-time 30 \
  -H 'Accept: text/markdown, text/x-markdown;q=0.95, text/html;q=0.9, application/xhtml+xml;q=0.9, text/plain;q=0.8' \
  -o "$page" -w '%{http_code}\t%{content_type}\t%{url_effective}' "$url") || exit 1
IFS=$'\t' read -r code type final <<<"$reply"

if [[ $code != 2?? ]]; then
  echo "read-page: $url answered $code" >&2
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
