#!/bin/sh
# SessionStart hook for sandboxed Claude sessions, added by nono/launch-agent:
# the AWS capability summary nono/tools/gen-aws.py wrote, so the agent knows
# what its read-only profiles cannot fetch before its first aws call.
f="$HOME/.local/share/nono-agent/aws-context.md"
[ ! -r "$f" ] || exec cat "$f"
