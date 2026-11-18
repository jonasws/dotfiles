#!/usr/bin/env python3
"""PreToolUse hook for Bash: auto-allow plain help and version queries.

Allows `tuios --help`, `git commit --help`, `rg --version` and chains of
them (`tuios --help; mise --help`). The rules are in help_only.py. On a
match it prints an allow decision, otherwise nothing, so the normal
permission flow decides. Deny and ask rules, and other hooks returning ask or
deny (pane-control-guard), still win over this allow.

It fails open: with no decision the call just goes through the usual prompt.

`python3 -I help-allow.py --self-test` checks help_only.py's tables.
"""

import importlib.util
import json
import os
import sys


def load_help_only():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "help_only.py")
    spec = importlib.util.spec_from_file_location("help_only", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    help_only = load_help_only()
    if "--self-test" in sys.argv:
        return 1 if help_only.self_test() else 0
    try:
        data = json.load(sys.stdin)
        command = (data.get("tool_input") or {}).get("command") or ""
        if data.get("tool_name") == "Bash" and help_only.is_help_only(command):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "help/version query only",
            }}))
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
