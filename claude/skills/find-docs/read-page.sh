#!/usr/bin/env bash
# Read a web page as markdown: the server's own markdown or plain text when it
# has one, otherwise its HTML converted by defuddle.
#
# Usage: read-page.sh <url>
#
# On a terminal the page opens in leaf; otherwise the markdown goes to stdout,
# so `read-page.sh <url> > page.md` gives a file to grep. Nothing reaches stdout
# or leaf unless a page came back: on failure the reason goes to stderr and the
# exit status is 1. A conversion is announced on stderr, because an extraction
# can drop what the page itself had.
set -euo pipefail

url=${1:?usage: read-page.sh <url>}
page=$(mktemp "${TMPDIR:-/tmp}/read-page.XXXXXX")
trap 'rm -f "$page"' EXIT

# One request that prefers markdown and accepts HTML, so a server with both
# picks markdown and one with only HTML still answers 2xx.
reply=$(curl -sSL --max-time 30 \
  -H 'Accept: text/markdown, text/x-markdown;q=0.95, text/html;q=0.9, application/xhtml+xml;q=0.9, text/plain;q=0.8' \
  -o "$page" -w '%{http_code} %{content_type}' "$url" 2>/dev/null) || reply="000 "
code=${reply%% *}
type=${reply#* }

case "$code $type" in
  # Plain text such as llms.txt is already readable as markdown.
  2??\ text/markdown* | 2??\ text/x-markdown* | 2??\ text/plain*) ;;
  *)
    if [[ $code == 000 ]]; then
      echo "read-page: the request to $url failed; trying defuddle" >&2
    else
      echo "read-page: $url answered $code ${type:-without a content type}; converting with defuddle" >&2
    fi
    # defuddle fetches again with the URL rather than taking the body on stdin:
    # it needs the URL to resolve relative links and to pick site extractors.
    # It accepts only 2xx HTML and says why on stderr otherwise.
    defuddle parse "$url" --md -o "$page" >/dev/null || exit 1
    ;;
esac

if [[ ! -s $page ]]; then
  echo "read-page: $url produced no content" >&2
  exit 1
fi

if [[ -t 1 ]]; then
  leaf <"$page"
else
  cat "$page"
fi
