#!/usr/bin/env bash
# Backend for the `jira` tv channel (cable/mine/jira.toml), over Jira's REST
# API with a read-only scoped API token. Scoped tokens only work through
# Atlassian's gateway (api.atlassian.com/ex/jira/<cloudId>), not the site URL.
#
#   jira.sh list '<jql>' [limit]  one aligned row per issue, served from cache
#   jira.sh preview KEY           the issue as Markdown, rendered by leaf
#   jira.sh open KEY              the issue in the browser
#
# A list prints its last result at once and, when that is over a minute old,
# refetches in the background; the channel's `watch` picks up the new rows. The
# same search carries every issue's rendered description, so a preview never
# calls Jira. Credentials and site come from the "Atlassian API Token" item in
# 1Password, through fnox.

set -euo pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}/tv-jira"
stale_after=60
fields=summary,status,assignee,reporter,parent,issuetype,priority,labels,created,updated,description

# One fnox request for every value, as fnox-secret makes it, so the daemon
# answers from the same warm cache. The export runs in a subshell and only the
# four values leave it.
creds() {
  local out
  out="$(
    eval "$(fnox -c "$HOME/.config/fnox/config.toml" --non-interactive export --all -f shell)"
    printf '%s\n' "$JIRA_HOST" "$JIRA_EMAIL" "$JIRA_API_TOKEN" "$JIRA_CLOUD_ID"
  )"
  { read -r host; read -r email; read -r token; read -r cloud; } <<<"$out"
  case "$host" in http://* | https://*) ;; *) host="https://$host" ;; esac
}

# The search response for one JQL on stdout. The credentials reach curl on
# stdin, so they never show in `ps`.
search() {
  local body
  body="$(jq -nc --arg jql "$1" --arg f "$fields" --argjson n "$2" \
    '{jql: $jql, fields: ($f | split(",")), maxResults: $n, expand: "renderedFields"}')"
  printf 'user = "%s:%s"\n' "$email" "$token" |
    curl -sS --fail-with-body --compressed -K - -X POST \
      "https://api.atlassian.com/ex/jira/$cloud/rest/api/3/search/jql" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data "$body"
}

# Fetch into $3 atomically, and split the issues into issue/<KEY>.json for the
# preview. A failed fetch leaves the previous list in place.
fetch() {
  local tmp
  creds
  mkdir -p "$cache/list" "$cache/issue"
  tmp="$(mktemp "$cache/list/.fetch.XXXXXX")"
  if search "$1" "$2" >"$tmp" && jq -e '.issues | type == "array"' "$tmp" >/dev/null; then
    jq -r '.issues[] | .key + "\t" + tojson' "$tmp" |
      while IFS=$'\t' read -r key json; do
        printf '%s' "$json" >"$cache/issue/$key.json"
      done
    mv "$tmp" "$3"
  else
    rm -f "$tmp"
    return 1
  fi
}

# The search JSON on stdin, one aligned row per issue:
#   key  lane  priority type  age  assignee  summary  ‹epic›
# Column widths are the widest value in the list, so the rows line up; summary
# and epic are last because they vary most. Lanes run right to left across the
# board (in progress before to do), rank order within each. The lane is
# coloured by status category, as Jira colours its lozenges.
format() {
  jq -r '
    def trunc($n): if length > $n then .[:$n - 1] + "…" else . end;
    def pad($n): if length < $n then . + (" " * ($n - length)) else . end;
    def age:
      (now - (.[:19] + "Z" | fromdateiso8601)) as $s |
      if $s < 3600 then "\($s / 60 | floor)m"
      elif $s < 86400 then "\($s / 3600 | floor)h"
      elif $s < 2592000 then "\($s / 86400 | floor)d"
      elif $s < 31536000 then "\($s / 2592000 | floor)mo"
      else "\($s / 31536000 | floor)y" end;
    def kind:
      {"Bug": "B", "Story": "S", "Task": "T", "Epic": "E", "Sub-task": "s", "Subtask": "s"}[.] // .[:1];
    [.issues[] | .fields + {key} | {
      key,
      summary,
      lane: .status.name,
      cat: (.status.statusCategory.key // ""),
      prio: (.priority.name // "-"),
      kind: (.issuetype.name // "?" | kind),
      age: (.updated // "" | if . == "" then "" else age end),
      who: (.assignee.displayName // "unassigned" | trunc(18)),
      epic: (.parent.fields.summary // "" | trunc(30))
    }]
    | sort_by({"indeterminate": 0, "new": 1}[.cat] // 2)
    | (map(.key | length) | max) as $wk
    | (map(.lane | length) | max) as $wl
    | (map(.prio | length) | max) as $wp
    | (map(.who | length) | max) as $ww
    | .[]
    | (if .cat == "done" then "32" elif .cat == "indeterminate" then "34" else "90" end) as $c
    | "\u001b[1m\(.key | pad($wk))\u001b[0m  \u001b[\($c)m\(.lane | pad($wl))\u001b[0m  \(.prio | pad($wp)) \(.kind)  \u001b[90m\(.age | pad(3))\u001b[0m  \u001b[33m\(.who | pad($ww))\u001b[0m  \(.summary)"
      + (if .epic == "" then "" else "  \u001b[2;35m‹\(.epic)›\u001b[0m" end)'
}

cmd="${1:-}"
shift || true

case "$cmd" in
  list)
    jql="$1"
    limit="${2:-100}"
    file="$cache/list/$(printf '%s|%s' "$jql" "$limit" | shasum | cut -c1-16).json"
    if [ ! -s "$file" ]; then
      fetch "$jql" "$limit" "$file"
    elif [ $(($(date +%s) - $(stat -f %m "$file"))) -gt "$stale_after" ] &&
      mkdir "$file.lock" 2>/dev/null; then
      # Detached from tv's pipe, so the cached rows show without waiting.
      (fetch "$jql" "$limit" "$file" || true; rmdir "$file.lock") </dev/null >/dev/null 2>&1 &
    fi
    format <"$file"
    ;;
  preview)
    file="$cache/issue/$1.json"
    [ -s "$file" ] || fetch "key = $1" 1 "$cache/list/.preview.json"
    {
      jq -r '
        .fields as $f |
        "# \(.key) \($f.summary)",
        "",
        "- **Lane:** \($f.status.name)",
        "- **Type:** \($f.issuetype.name // "-") · **Priority:** \($f.priority.name // "-")",
        "- **Assignee:** \($f.assignee.displayName // "unassigned") · **Reporter:** \($f.reporter.displayName // "-")",
        (if $f.parent then "- **Epic:** \($f.parent.key) \($f.parent.fields.summary)" else empty end),
        (if ($f.labels | length) > 0 then "- **Labels:** \($f.labels | join(", "))" else empty end),
        "- **Created:** \($f.created[:10]) · **Updated:** \($f.updated[:10])",
        "",
        "---",
        ""' "$file"
      jq -r '.renderedFields.description // ""' "$file" | pandoc -f html -t gfm --wrap=none
    } | leaf --inline ansi:100
    ;;
  open)
    creds
    open "$host/browse/$1"
    ;;
  *)
    echo "usage: jira.sh list JQL [LIMIT] | preview KEY | open KEY" >&2
    exit 2
    ;;
esac
