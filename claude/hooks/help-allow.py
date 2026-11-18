#!/usr/bin/env python3
"""PreToolUse hook for Bash: auto-allow plain help and version queries.

Allows `tuios --help`, `git commit --help`, `rg --version` and chains of
them (`tuios --help; mise --help`). The rules are in help_only.py. On a
match it prints an allow decision, otherwise nothing, so the normal
permission flow decides. Deny and ask rules, and other hooks returning ask or
deny (pane-control-guard), still win over this allow.

Commands in ASK_COMMANDS get an ask decision instead whenever they are not
help-only. They stand in for a settings ask rule such as `Bash(twg:*)`,
which would also catch `twg --help` and outrank the allow above.

It fails open for the allow: with no decision the call just goes through the
usual prompt. A command naming an ASK_COMMANDS entry still gets ask when the
input cannot be parsed.

`python3 -I help-allow.py --self-test` checks the tables here and in
help_only.py.
"""

import importlib.util
import json
import os
import re
import sys

# twg writes to Jira and Confluence; its read commands are not told apart here.
ASK_COMMANDS = {"twg": "twg can write to Jira and Confluence"}
# A word on its own, not part of a path (~/.config/twg/...) or a longer name.
ASK_RE = re.compile(r"(?<![\w./-])(" + "|".join(map(re.escape, ASK_COMMANDS)) + r")(?![\w./-])")


def load_help_only():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "help_only.py")
    spec = importlib.util.spec_from_file_location("help_only", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def decide(help_only, command):
    if help_only.is_help_only(command):
        return "allow", "help/version query only"
    match = ASK_RE.search(command)
    if match:
        return "ask", ASK_COMMANDS[match.group(1)]
    return None, None


def emit(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}))


ASK = [
    "twg jira workitem create --summary x", "twg jira space list",
    "cd x && twg jira space list", "twg --help; twg jira space list",
    "mise exec -- twg confluence page get 1", "twg jira space --help > out",
]
ALLOW = ["twg --help", "twg -h", "twg jira space --help", "twg jira workitem create -h"]
NONE = ["cat ~/.config/twg/consent.json", "ls ~/Library/Caches/twg", "rg twg-jira x", "echo hi"]


def self_test(help_only):
    expected = [(c, "allow") for c in ALLOW] + [(c, "ask") for c in ASK] + [(c, None) for c in NONE]
    bad = [(c, want) for c, want in expected if decide(help_only, c)[0] != want]
    for c, want in bad:
        print(f"FAIL help-allow: {c!r} should be {want}")
    print(f"help-allow: {len(ALLOW)} allow, {len(ASK)} ask, {len(NONE)} none: {len(bad)} failed")
    return len(bad)


def main():
    help_only = load_help_only()
    if "--self-test" in sys.argv:
        return 1 if help_only.self_test() + self_test(help_only) else 0
    raw = ""
    try:
        raw = sys.stdin.read()
        data = json.loads(raw)
        command = (data.get("tool_input") or {}).get("command") or ""
        if data.get("tool_name") == "Bash":
            decision, reason = decide(help_only, command)
            if decision:
                emit(decision, reason)
    except Exception:
        match = ASK_RE.search(raw)
        if match:
            emit("ask", ASK_COMMANDS[match.group(1)])
    return 0


if __name__ == "__main__":
    sys.exit(main())
