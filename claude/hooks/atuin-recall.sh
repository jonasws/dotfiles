#!/usr/bin/env bash
# Claude Code hook: point a new session at earlier work that atuin captured.
#   session  (SessionStart): the newest agent threads started in this repo.
#   prompt   (UserPromptSubmit): a reminder to look earlier work up when the
#            prompt refers back to it.
# It prints nothing and exits 0 when atuin or jq is missing, so it never blocks.
set -u
command -v atuin >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)

emit() {
  jq -n --arg e "$1" --arg c "$2" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
}

case "${1:-}" in
session)
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  sid=$(jq -r '.session_id // empty' <<<"$input")
  [ -n "$cwd" ] || exit 0
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")
  # Subagent threads are listed too; leave out every thread that is another's child.
  rows=$(atuin threads list --style ndjson 2>/dev/null | jq -rs --arg root "$root" --arg sid "$sid" '
    ([.[].children_atuin_ids // [] | .[]] | INDEX(.)) as $children
    | [.[] | select(.cwd == $root or (.cwd // "" | startswith($root + "/")))
           | select(.session_id != $sid and ($children[.atuin_id] | not))][:3][]
    | "- \(.updated_at[:10]) \((.title // .preview // "untitled") | gsub("\\s+"; " ") | .[:90]) [\(.harness) \(.atuin_id)]"')
  [ -n "$rows" ] || exit 0
  emit SessionStart "Newest agent threads in this repo (atuin_threads_read takes the id):
$rows"
  ;;
prompt)
  jq -e '(.prompt // "") | test("\\b(again|last time|like before|as before|previously|continue|resume|pick up|still|forrige gang|igjen|som sist|fortsett|tidligere)\\b"; "i")' \
    <<<"$input" >/dev/null 2>&1 || exit 0
  emit UserPromptSubmit "This prompt may refer to earlier work. Look it up before acting: atuin_threads_search for what was tried or decided, atuin search --cwd . --exit 0 <terms> for commands that worked."
  ;;
esac
exit 0
