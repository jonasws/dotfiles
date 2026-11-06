#!/usr/bin/env bash
# PreToolUse hook for the AWS MCP `run_script` tool.
#
# Shows the proposed script read-only in nvim, in a tuios popup, and returns at
# once. It decides nothing and never touches the tool input: Claude Code's own
# permission prompt (run_script is set to "ask") stays the only gate, so there
# is no hook timeout to race. The popup stays open until you quit nvim (:q);
# nvim deletes the temp script when it exits.
#
# Outside tuios, or without jq/tuios/nvim, the hook does nothing.

set -uo pipefail

[ "${TUIOS_ENV:-}" = "1" ] || exit 0
for bin in jq tuios nvim; do
  command -v "$bin" >/dev/null 2>&1 || exit 0
done

code=$(jq -r '.tool_input.code // empty')
[ -n "$code" ] || exit 0

dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-run-script.XXXXXX") || exit 0
file="$dir/run_script.py"
printf '%s\n' "$code" >"$file"

# -M: not modifiable, not writable. Diagnostics off so the python LSP does not
# decorate the boto3 snippet with warnings.
tuios popup --width 90% --height 85% -- nvim -M \
  -c 'set filetype=python number' \
  -c 'lua vim.diagnostic.enable(false)' \
  -c "autocmd VimLeave * call delete('$file') | call delete('$dir', 'd')" \
  "$file" >/dev/null 2>&1 || true

exit 0
