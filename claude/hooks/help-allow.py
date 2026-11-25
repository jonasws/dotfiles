#!/usr/bin/env python3
"""PreToolUse hook for Bash: auto-allow plain help and version queries.

Allows `tuios --help`, `git commit --help`, `rg --version` and chains of
them (`tuios --help; mise --help`), and the reference forms `twg --skill` and
`tuios --skill tml` that print a CLI's own usage guide. A bare `skill` word is
not one: in `rm skill` or `git commit skill` it is an argument. The rules are in
help_only.py. On a
match it prints an allow decision, otherwise nothing, so the normal
permission flow decides. Deny and ask rules, and other hooks returning ask or
deny (pane-control-guard), still win over this allow.

Commands in ASK_COMMANDS get an ask decision instead whenever they are not
help-only. They stand in for a settings ask rule such as `Bash(twg:*)`,
which would also catch `twg --help` and outrank the allow above.

atuin is split by form (atuin_decision): plain reads such as `atuin search
<query>` are allowed, and every other atuin call, `search --delete` among
them, gets ask. A settings rule cannot do this, since `Bash(atuin search *)`
also matches `atuin search --delete`.

It fails open for the allow: with no decision the call just goes through the
usual prompt. A command naming an ASK_COMMANDS entry or running atuin still
gets ask when the input cannot be parsed.

`python3 -I help-allow.py --self-test` checks the tables here and in
help_only.py.
"""

import importlib.util
import json
import os
import re
import shlex
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


# atuin forms that only read history, threads or the store.
ATUIN_READ = {
    ("search",), ("stats",), ("info",), ("history", "list"), ("history", "last"),
    ("output", "search"), ("threads", "list"), ("threads", "show"), ("threads", "search"),
    ("store", "status"), ("store", "verify"), ("kv", "get"), ("kv", "list"),
    ("scripts", "list"), ("scripts", "get"),
}
ATUIN_GROUPS = {"history", "output", "threads", "store", "kv", "scripts"}
# Programs an atuin read may pipe into: none of them writes a file or runs one.
ATUIN_SINKS = {"head", "tail", "wc", "jq"}
ATUIN_CMD_RE = re.compile(r"(^|[;&|(\n]\s*)(\S*/)?atuin\s")
DEVNULL_RE = re.compile(r"\s2>/dev/null(?=\s|\||$)")
OPERATOR_RE = re.compile(r"^[;&|<>()]+$")
ATUIN_ASK = "atuin call that may change or send history"


def _expands(command):
    """True when the shell would expand $ or a backtick outside single quotes."""
    quote = None
    for ch in command:
        if quote == "'":
            if ch == "'":
                quote = None
        elif ch in "$`":
            return True
        elif ch == quote:
            quote = None
        elif quote is None and ch in "'\"":
            quote = ch
    return False


def _tokens(command):
    lexer = shlex.shlex(DEVNULL_RE.sub("", command), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    return list(lexer)


def atuin_decision(command):
    """allow for a read-only atuin call, ask for any other atuin call, None otherwise."""
    try:
        tokens = _tokens(command)
    except ValueError:
        return "ask" if ATUIN_CMD_RE.search(command) else None
    segments, current = [], []
    for tok in tokens:
        if OPERATOR_RE.match(tok):
            segments.append((current, tok))
            current = []
        else:
            current.append(tok)
    segments.append((current, None))
    words = [seg[0] if seg else "" for seg, _ in segments]
    if not any(w == "atuin" or w.endswith("/atuin") for w in words):
        return None
    if "\n" in command or _expands(command):
        return "ask"
    if any(op not in (None, "|") for _, op in segments):
        return "ask"
    first = segments[0][0]
    if not first or first[0] != "atuin" or len(first) < 2:
        return "ask"
    if any(t.startswith("--del") for t in first):
        return "ask"
    if any(seg[0] not in ATUIN_SINKS for seg, _ in segments[1:] if seg) or any(not seg for seg, _ in segments[1:]):
        return "ask"
    form = tuple(first[1:3]) if first[1] in ATUIN_GROUPS else (first[1],)
    if form not in ATUIN_READ:
        return "ask"
    if form == ("search",) and any(t in ("-i", "--interactive") for t in first):
        return None
    return "allow"


def decide(help_only, command):
    if help_only.is_help_only(command):
        return "allow", "help/version query only"
    if help_only.is_reference_query(command):
        return "allow", "help or skill reference query only"
    atuin = atuin_decision(command)
    if atuin == "allow":
        return "allow", "read-only atuin query"
    if atuin == "ask":
        return "ask", ATUIN_ASK
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
    "twg skill install x", "twg skill install", "twg --skill > out", "twg --skill; twg jira space list",
]
ALLOW = ["twg --help", "twg -h", "twg jira space --help", "twg jira workitem create -h",
         "twg --skill", "twg --skill jira", "tuios --skill tml", "mise --help; twg --skill"]
NONE = ["cat ~/.config/twg/consent.json", "ls ~/Library/Caches/twg", "rg twg-jira x", "echo hi",
        "rm skill", "git commit skill"]

ATUIN_ALLOW = [
    "atuin search --exit 0 --cwd . 'deploy'",
    "atuin search --author '$all-agent' --limit 20 tuios",
    "atuin search --print0 --format '{time}\\t{command}' x 2>/dev/null | head -20",
    "atuin threads list --style ndjson | jq -r '.title'",
    "atuin history list --cmd-only | tail -5", "atuin stats", "atuin threads show latest",
    "atuin output search ENOSPC", "atuin kv get foo", "atuin info", "atuin --help",
]
ATUIN_ASK_CASES = [
    "atuin search foo --delete", "atuin search --delete-it-all", "atuin search -- --delete",
    "atuin history prune", "atuin history dedup", "atuin history start -- ls", "atuin store purge",
    "atuin kv set a b", "atuin threads import", "atuin resume", "atuin ai", "atuin sync", "atuin key",
    "atuin search x | sh", "atuin search x > out.txt", "atuin search x; rm y",
    "atuin search \"$(id)\"", "atuin search --author \"$USER\" x", "atuin search x | jq . | tee f",
    "atuin search x && atuin history dedup", "cd x && atuin search y", "atuin", "atuin search 'x",
    "atuin search x &",
]
ATUIN_NONE = [
    "rg atuin ~/dotfiles", "cat ~/.atuin/config.toml", "ls ~/.local/share/atuin",
    "echo atuin", "atuin search -i deploy",
]


def self_test(help_only):
    expected = [(c, "allow") for c in ALLOW + ATUIN_ALLOW] + [(c, "ask") for c in ASK + ATUIN_ASK_CASES]
    expected += [(c, None) for c in NONE + ATUIN_NONE]
    bad = [(c, want) for c, want in expected if decide(help_only, c)[0] != want]
    for c, want in bad:
        print(f"FAIL help-allow: {c!r} should be {want}")
    print(f"help-allow: {len(ALLOW) + len(ATUIN_ALLOW)} allow, {len(ASK) + len(ATUIN_ASK_CASES)} ask, "
          f"{len(NONE) + len(ATUIN_NONE)} none: {len(bad)} failed")
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
        elif ATUIN_CMD_RE.search(raw):
            emit("ask", ATUIN_ASK)
    return 0


if __name__ == "__main__":
    sys.exit(main())
