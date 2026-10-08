#!/usr/bin/env bash
# PreToolUse hook for the AWS agent toolkit `run_script` tool.
#
# Opens the proposed script in $EDITOR in a new herdr pane to the right, waits
# for the editor to exit, and hands the edited script back to Claude through
# `updatedInput` so the tool call runs the reviewed version.
#
# Editor exit conventions:
#   save + quit            edited script is used, tool call is auto-approved
#   quit without saving    original script is used, normal permission flow
#   non-zero exit (:cq)    tool call is denied
#   empty buffer           tool call is denied
#
# The command is handed to the new pane through HERDR_EXEC_CMD (see
# fish/conf.d/50-herdr-exec.fish) because `herdr pane split` has no --command
# flag and typing the command in with `herdr pane run` races the shell's
# startup: text sent too early is dropped, and a resend after the editor has
# started is swallowed by the editor as keystrokes. `herdr pane run` is kept
# only as a fallback for shells without that snippet.
#
# Requires: jq, herdr, HERDR_ENV=1. Outside herdr the hook does nothing.

set -uo pipefail

TOOL_MATCH="${AWS_RUN_SCRIPT_TOOL:-mcp__aws__aws___run_script}"
CODE_FIELD="${AWS_RUN_SCRIPT_FIELD:-code}"
EDIT_TIMEOUT="${AWS_RUN_SCRIPT_EDIT_TIMEOUT:-1500}"
START_TIMEOUT="${AWS_RUN_SCRIPT_START_TIMEOUT:-15}"
# "allow" skips the permission prompt for a script you just reviewed. Set to
# "ask" to keep Claude's normal confirmation on top of the edit.
DECISION="${AWS_RUN_SCRIPT_DECISION:-allow}"

PANE=""

restore_focus() {
  [ -n "${HERDR_PANE_ID:-}" ] || return 0
  herdr agent focus "$HERDR_PANE_ID" >/dev/null 2>&1 || true
}

cleanup_pane() {
  [ -n "$PANE" ] || return 0
  herdr pane close "$PANE" >/dev/null 2>&1 || true
  restore_focus
}

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Not inside herdr, or missing tooling: stay out of the way entirely.
command -v jq >/dev/null 2>&1 || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0

INPUT=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$INPUT")" = "$TOOL_MATCH" ] || exit 0

CODE=$(jq -r --arg f "$CODE_FIELD" '.tool_input[$f] // empty' <<<"$INPUT")
[ -n "$CODE" ] || exit 0

CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[ -n "$CWD" ] || CWD="$PWD"

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-run-script.XXXXXX") || exit 0
trap 'rm -rf "$WORKDIR"' EXIT

SCRIPT="$WORKDIR/run_script.py"
STATUS="$WORKDIR/status"
STARTED="$WORKDIR/started"
RUNNER="$WORKDIR/edit.sh"

printf '%s\n' "$CODE" >"$SCRIPT"

# Shell-agnostic runner: the pane starts whichever login shell is configured.
# The `started` marker keeps a fallback resend from opening a second editor.
EDIT_CMD="${VISUAL:-${EDITOR:-vi}}"
cat >"$RUNNER" <<EOF
#!/bin/sh
[ -f "$STARTED" ] && exit 0
: >"$STARTED"
\${CLAUDE_EDIT_CMD:-vi} "$SCRIPT"
printf '%s' "\$?" >"$STATUS"
EOF

SPLIT=$(herdr pane split --pane "$HERDR_PANE_ID" --direction right --cwd "$CWD" \
  --env "CLAUDE_EDIT_CMD=$EDIT_CMD" \
  --env "HERDR_EXEC_CMD=sh '$RUNNER'" \
  --focus 2>&1) ||
  deny "Could not open a herdr pane to review the script: $SPLIT"
PANE=$(jq -r '.result.pane.pane_id // empty' <<<"$SPLIT")
[ -n "$PANE" ] || deny "herdr pane split returned no pane id"

herdr pane rename "$PANE" "review run_script" >/dev/null 2>&1

# Wait for the pane to pick up HERDR_EXEC_CMD. If the shell has no such
# snippet, type the command in once instead (safe here: the editor is provably
# not running yet, so nothing can swallow the keystrokes).
FALLBACK_SENT=0
DEADLINE=$((SECONDS + START_TIMEOUT))
while [ ! -f "$STARTED" ] && [ "$SECONDS" -lt "$DEADLINE" ]; do
  if [ "$FALLBACK_SENT" -eq 0 ] && [ "$SECONDS" -ge $((DEADLINE - START_TIMEOUT + 6)) ]; then
    herdr pane run "$PANE" "sh '$RUNNER'" >/dev/null 2>&1
    FALLBACK_SENT=1
  fi
  herdr pane get "$PANE" >/dev/null 2>&1 || break
  sleep 0.25
done
[ -f "$STARTED" ] || {
  cleanup_pane
  deny "Could not start \$EDITOR in the review pane; script not run."
}

# Wait for the editor to exit. The pane closes itself once the command is done,
# so a vanished pane is expected, not an error.
DEADLINE=$((SECONDS + EDIT_TIMEOUT))
while [ ! -f "$STATUS" ] && [ "$SECONDS" -lt "$DEADLINE" ]; do
  if ! herdr pane get "$PANE" >/dev/null 2>&1; then
    PANE=""
    sleep 0.5
    break
  fi
  sleep 0.3
done

cleanup_pane
restore_focus

[ -f "$STATUS" ] || deny "Review pane closed or timed out before the editor finished; script not run."

EDITOR_STATUS=$(cat "$STATUS" 2>/dev/null)
[ "$EDITOR_STATUS" = "0" ] || deny "Editor exited with status ${EDITOR_STATUS:-unknown}; script not run."

NEW_CODE=$(cat "$SCRIPT" 2>/dev/null)
[ -n "${NEW_CODE//[[:space:]]/}" ] || deny "Script was emptied in the editor; treating as abort."

# Unchanged: stay out of the way and let the normal permission flow decide.
[ "$NEW_CODE" != "$CODE" ] || exit 0

jq -n \
  --argjson input "$INPUT" \
  --arg field "$CODE_FIELD" \
  --arg code "$NEW_CODE" \
  --arg decision "$DECISION" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $decision,
      permissionDecisionReason: "Script edited in $EDITOR before running",
      updatedInput: ($input.tool_input + {($field): $code})
    }
  }'
