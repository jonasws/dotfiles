#!/usr/bin/env python3
"""PreToolUse hook for Bash: always ask before herdr or tuios commands that
read from a pane, type into a pane, or launch a new one.

Those commands let an agent drive other terminals (and other agents) on its
own, so each one gets a prompt in every permission mode, auto mode included:
a hook's "ask" is shown even where an allow rule or the classifier would
have approved the call.

The command text is searched for herdr/tuios invocations wherever they sit:
after `&&` or `;`, behind a path, `env`, `xargs` or `mise exec --`, inside
`bash -c '...'`, `$(...)` or a heredoc. Script files named on the command
line (.sh, .py, ...) are searched too, one level deep, because a skill
script can run `herdr pane split` or `tuios split-window` itself.

It errs towards asking: a prompt costs one keypress, a miss costs a pane the
user never approved. Not covered: a program that talks to the herdr or tuios
socket directly, and commands assembled at run time (`$cmd` is asked about,
a string built in a script's own variables is not).

`python3 pane-control-guard.py --self-test` checks the tables below.
"""

import json
import os
import re
import shlex
import sys

READ, TYPE, LAUNCH = "read", "type", "launch"
WHAT = {
    READ: "reads pane output",
    TYPE: "types into a pane or agent",
    LAUNCH: "launches a pane, tab, workspace or agent",
}

# (group, subcommand) as printed by `herdr <group> --help`.
HERDR = {
    ("pane", "read"): READ,
    ("pane", "wait-output"): READ,
    ("agent", "read"): READ,
    ("agent", "explain"): READ,
    ("pane", "run"): TYPE,
    ("pane", "send-text"): TYPE,
    ("pane", "send-keys"): TYPE,
    ("pane", "input"): TYPE,
    ("agent", "send-keys"): TYPE,
    ("agent", "prompt"): TYPE,
    ("pane", "split"): LAUNCH,
    ("tab", "create"): LAUNCH,
    ("workspace", "create"): LAUNCH,
    ("worktree", "create"): LAUNCH,
    ("worktree", "open"): LAUNCH,
    ("agent", "start"): LAUNCH,
}

# Top-level subcommands from `tuios --help`. `call`, `run-command`, `tape`,
# `tmux`, `tmux-shim` and `mcp` can issue any of the others, so they count as
# typing.
TUIOS = {
    "capture-pane": READ,
    "pane-view": READ,
    "screenshot": READ,
    "agent-log": READ,
    "peek-prompt": READ,
    "explain-agent-detect": READ,
    "explain-agent-screen": READ,
    "subscribe": READ,
    "run": TYPE,
    "send-text": TYPE,
    "send-keys": TYPE,
    "paste-buffer": TYPE,
    "queue": TYPE,
    "respond": TYPE,
    "ask-agent": TYPE,
    "resume-agent": TYPE,
    "call": TYPE,
    "run-command": TYPE,
    "tape": TYPE,
    "tmux": TYPE,
    "tmux-shim": TYPE,
    "mcp": TYPE,
    "new-window": LAUNCH,
    "split-window": LAUNCH,
    "start-agent": LAUNCH,
    "fan": LAUNCH,
    "popup": LAUNCH,
    "xpanes": LAUNCH,
    "new": LAUNCH,
    "worktree": LAUNCH,
    "resurrect": LAUNCH,
}

# Options that come before the subcommand and take a value.
VALUE_OPTS = {
    "herdr": {"--session", "--machine", "--remote"},
    "tuios": {"-s", "--session", "-w", "--window"},
}

# The program name at a command position or inside a quoted string, not a
# longer word: herdr-agent-state.sh and ~/.config/herdr/ do not match.
CALL = re.compile(r"""(?:^|[\s;&|(`'"=/])(herdr|tuios)(?=[\s'")`;&|]|$)""")
# Where an invocation's own arguments end.
BOUNDARY = re.compile(r"[;&|)\n`]|\$\(")
SCRIPT_EXT = {".sh", ".bash", ".zsh", ".fish", ".py", ".js", ".mjs", ".ts", ".rb", ".pl", ".lua"}
MAX_SCRIPT_BYTES = 256 * 1024
MAX_SCRIPTS = 8
UNKNOWN = "unknown"


def invocations(text):
    for m in CALL.finditer(text):
        tail = BOUNDARY.split(text[m.end():m.end() + 400], 1)[0]
        try:
            args = shlex.split(tail)
        except ValueError:
            args = tail.split()
        yield m.group(1), args


def classify(prog, args):
    """Return (name, kind) for a sensitive invocation, else None."""
    opts = VALUE_OPTS[prog]
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in opts else 1
    rest = args[i:]
    if not rest:
        return None
    n = 2 if prog == "herdr" else 1
    words = rest[:n]
    if any(w.startswith(("$", "<")) for w in words):
        return (f"{prog} {' '.join(words)}", UNKNOWN)
    if prog == "tuios":
        kind = TUIOS.get(words[0])
    else:
        kind = HERDR.get(tuple(words))
    return (f"{prog} {' '.join(words)}", kind) if kind else None


def hits_in(text):
    found = []
    for prog, args in invocations(text):
        hit = classify(prog, args)
        if hit and hit not in found:
            found.append(hit)
    return found


def script_hits(command, cwd):
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = command.split()
    self_path = os.path.realpath(__file__)
    seen, found = set(), []
    for token in tokens:
        if os.path.splitext(token)[1] not in SCRIPT_EXT or "$" in token:
            continue
        path = os.path.expanduser(token)
        if not os.path.isabs(path):
            path = os.path.join(cwd or os.getcwd(), path)
        path = os.path.realpath(path)
        if path in seen or path == self_path or not os.path.isfile(path):
            continue
        seen.add(path)
        if len(seen) > MAX_SCRIPTS or os.path.getsize(path) > MAX_SCRIPT_BYTES:
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        for hit in hits_in(text):
            found.append((os.path.basename(path),) + hit)
    return found


def reason(direct, scripts):
    lines = []
    for name, kind in direct:
        if kind == UNKNOWN:
            lines.append(f"`{name}`: the subcommand is a variable, so it can't be checked")
        else:
            lines.append(f"`{name}` {WHAT[kind]}")
    for script, name, kind in scripts:
        what = "can't be checked" if kind == UNKNOWN else WHAT[kind]
        lines.append(f"{script} runs `{name}`, which {what}")
    return "Pane control: " + "; ".join(lines) + ". Check the target pane and what it will run."


def evaluate(command, cwd=None):
    direct = hits_in(command)
    scripts = script_hits(command, cwd)
    return reason(direct, scripts) if direct or scripts else None


def main():
    if "--self-test" in sys.argv:
        return self_test()
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    if data.get("tool_name") != "Bash":
        return 0
    command = (data.get("tool_input") or {}).get("command")
    if not isinstance(command, str) or not command:
        return 0
    try:
        why = evaluate(command, data.get("cwd"))
    except Exception as e:  # a broken guard asks rather than waves through
        why = f"pane-control-guard failed ({type(e).__name__}: {e}); asking instead"
    if why:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": why,
        }}))
    return 0


ASK = [
    ("herdr pane read w1:p2 --lines 20", READ),
    ("herdr pane run p 'ls -la'", TYPE),
    ("herdr --session foo pane send-keys p enter", TYPE),
    ("cd /tmp && herdr pane split --current --direction right", LAUNCH),
    ("~/.local/bin/herdr agent prompt reviewer 'hi'", TYPE),
    ("bash -c 'herdr pane run p ls'", TYPE),
    ('sh -c "herdr pane run p ls; echo done"', TYPE),
    ("echo $(herdr pane read p)", READ),
    ("env FOO=1 herdr tab create --label x", LAUNCH),
    ("mise exec -- herdr workspace create", LAUNCH),
    ("xargs -I{} herdr pane run {} ls", TYPE),
    ("herdr agent send-keys reviewer esc", TYPE),
    ("herdr pane wait-output p --match done", READ),
    ("herdr agent start claude --pane p", LAUNCH),
    ("tuios send-text -s dotfiles -w build 'ls'", TYPE),
    ("tuios -s x capture-pane -w y", READ),
    ('tuios new-window -s "$TUIOS_SESSION" slides --no-focus -- ls', LAUNCH),
    ("tuios split-window -s s right --no-focus -- tail -f x", LAUNCH),
    ("tuios run -s s -w build --timeout 600000 -- make test", TYPE),
    ("tuios -w build send-keys ctrl+c", TYPE),
    ("tuios fan 3 'do the thing'", LAUNCH),
    ("tuios start-agent claude -- --model x", LAUNCH),
    ("tuios queue -s s -w review 'then migrate'", TYPE),
    ("tuios call send-text", TYPE),
    ("tuios list-windows; tuios send-keys enter", TYPE),
    ("herdr pane $SUB p", UNKNOWN),
]
PASS = [
    "herdr pane list", "herdr pane current", "herdr pane get p", "herdr pane focus p",
    "herdr workspace list", "herdr tab list", "herdr agent list", "herdr agent wait x --state idle",
    "herdr status", "herdr --version", "herdr", "herdr pane close p",
    "tuios list-windows", "tuios ls", "tuios list-agents -s s", "tuios --skill",
    "tuios note set 'next: run migration'", "tuios ask-human 'run it?' -o yes -o no",
    "tuios send-agent-message -s s -w a 'hi'", "tuios mermaid f.mmd", "tuios task block 3 'stuck'",
    "rg -n herdr settings.json", "ls ~/.config/herdr/plugins.json",
    "bash ~/.claude/hooks/herdr-agent-state.sh session", "git status",
    "mise exec aqua:mfontanini/presenterm@latest -- presenterm deck.md",
]


def self_test():
    import tempfile

    failures = 0

    def check(label, got, want):
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")

    for command, want in ASK:
        check(command, [k for _, k in hits_in(command)][:1], [want])
    for command in PASS:
        check(command, hits_in(command), [])
    with tempfile.TemporaryDirectory() as d:
        hit = os.path.join(d, "viewer.sh")
        quiet = os.path.join(d, "quiet.sh")
        with open(hit, "w") as f:
            f.write('#!/bin/sh\nherdr pane split --current\nherdr pane run "$P" ls\n')
        with open(quiet, "w") as f:
            f.write("#!/bin/sh\nherdr pane list\n")
        check("script with hits", bool(evaluate(f"bash {hit}", d)), True)
        check("script, relative path", bool(evaluate("bash viewer.sh", d)), True)
        check("script without hits", evaluate(f"bash {quiet}", d), None)
        check("missing script", evaluate("bash /nonexistent/x.sh", d), None)
    out = evaluate("herdr pane run p ls")
    check("reason text", bool(out) and "types into a pane" in out, True)
    print(f"{len(ASK)} ask, {len(PASS)} pass, 4 script cases: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
