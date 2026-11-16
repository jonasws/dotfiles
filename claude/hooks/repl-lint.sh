#!/usr/bin/env bash
# PreToolUse hook for Code Mode's REPL tool: lint tool_input.code with ast-grep.
# A linter for mistakes an honest model makes, not a security boundary: a script
# written to get past it will. Security comes from the per-call permission rules
# and hooks every tool call from a script still meets, and from the OS sandbox.
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

# Rule severity picks the outcome: error denies (the script is wrong, the model
# rewrites it), warning asks (it may be intended, the user decides).
"$JQ" -c '
  def fmt: "line \(.range.start.line + 1): \(.message)";
  def cap: if length > 10 then .[:10] + ["and \(length - 10) more"] else . end;
  def decide($d; $r): {hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: $d, permissionDecisionReason: ("repl-lint: " + ($r | cap | join("; ")))}};
  def findings($s): [.[] | select(.severity == $s)] | unique_by([.range.start.line, .message]) | map(fmt);
  findings("error") as $e
  | findings("warning") as $w
  | if ($e | length) > 0 then decide("deny"; $e)
    elif ($w | length) > 0 then decide("ask"; $w)
    else empty end' <<<"$out" || fail "could not parse scanner output"
