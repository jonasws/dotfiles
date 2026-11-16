#!/usr/bin/env bash
# PreToolUse hook for Code Mode's REPL tool: lint tool_input.code with ast-grep.
# Hygiene only. Security comes from the session-taint hook and the OS sandbox.
# Any failure exits 2, which refuses the script: a broken linter must not wave code through.
set -o pipefail
RULES="${REPL_LINT_RULES:-$HOME/.claude/repl-lint}"

fail() { echo "repl-lint: $1" >&2; exit 2; }

# A mise shim costs ~100 ms per call; take the first real binary on PATH.
pick() {
  local p
  for p in $(type -ap "$1"); do
    case "$p" in */mise/shims/*) continue ;; esac
    echo "$p"; return 0
  done
  type -P "$1"
}
SG=$(pick ast-grep) || fail "ast-grep not on PATH"
JQ=$(pick jq) || fail "jq not on PATH"

# ast-grep picks the language from the file extension, and BSD mktemp has no --suffix.
dir=$(mktemp -d "${TMPDIR:-/tmp}/repl-lint.XXXXXX") || fail "mktemp failed"
trap 'rm -f "$dir/script.js"; rmdir "$dir"' EXIT
"$JQ" -r '.tool_input.code // empty' > "$dir/script.js" || fail "could not read hook input"
[ -s "$dir/script.js" ] || exit 0

out=$("$SG" scan -c "$RULES/sgconfig.yml" --json=compact "$dir/script.js" 2>/dev/null)
[ -z "$out" ] && fail "scanner produced no output"

result=$("$JQ" -r '
  def fmt: "line \(.range.start.line + 1): \(.message)";
  ([.[] | select(.severity == "error") | fmt] | unique) as $e
  | ([.[] | select(.severity == "warning") | fmt] | unique) as $w
  | if ($e | length) > 0 then
      {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
        permissionDecisionReason: ("REPL policy: " + ($e | join("; ")))}} | tojson
    elif ($w | length) > 0 then "warn\t" + ($w | join("; "))
    else empty end' <<<"$out") || fail "could not parse scanner output"

case "$result" in
  "") ;;
  warn$'\t'*) echo "repl-lint warnings: ${result#warn$'\t'}" >&2 ;;
  *) printf '%s\n' "$result" ;;
esac
exit 0
