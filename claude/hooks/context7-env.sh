#!/bin/sh
# SessionStart hook: puts CONTEXT7_API_KEY into the environment of every Bash
# command in the session, so Context7 API calls authenticate inside the sandbox.
#
# Hooks run outside the sandbox, so fnox-secret reaches the warm fnox daemon here
# and costs no Touch ID beyond the shared cold start. Sandboxed commands cannot
# resolve fnox themselves: the daemon socket is out of reach, and without it the
# Secure Enclave decrypt needs keychain services the sandbox rightly blocks.
#
# Every command in the session sees the key. That is acceptable for this one, a
# read-only docs quota, and is not a pattern for credentials that can write.
#
# SessionStart output becomes model context, so the key goes to the env file only.

[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
grep -q '^export CONTEXT7_API_KEY=' "$CLAUDE_ENV_FILE" 2>/dev/null && exit 0

key="$("$HOME/.local/bin/wrapped/fnox-secret" CONTEXT7_API_KEY 2>/dev/null)" || exit 0
printf "export CONTEXT7_API_KEY='%s'\n" "$key" >> "$CLAUDE_ENV_FILE"
