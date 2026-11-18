"""Shared check: is a Bash command nothing but help or version queries?

Used by help-allow.py, which auto-allows such commands, and by
pane-control-guard.py, which does not ask about them.

A segment passes only when it is a bare command name, then subcommand-like
words, then exactly one help flag (--help, -h, --version, -V), or `help` as
the first argument. Segments may be joined by ;, && or || and may pipe into
head, tail or wc. Any quote, expansion, redirect, glob, backslash or background
`&` rejects the whole command, as do wrappers that run another program (env,
xargs, sudo, ...) and names with a script extension (`run.sh --help` runs a
script from PATH that may ignore the flag).
"""

import os
import re

UNSAFE = re.compile(r"[`$<>(){}\\\"'*?\[\]~!#]")
SPLIT = re.compile(r";|&&|\|\||\n")
NAME = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.+-]*$")
WORD = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
HELP_FLAGS = {"--help", "-h", "--version", "-V"}
WRAPPERS = {
    "env", "xargs", "sudo", "doas", "time", "nohup", "exec", "eval", "command",
    "builtin", "watch", "timeout", "nice", "setsid", "script", "ssh", "sh",
    "bash", "zsh", "fish", "dash",
}
SCRIPT_EXT = {".sh", ".bash", ".zsh", ".fish", ".py", ".js", ".mjs", ".ts", ".rb", ".pl", ".lua"}
SINKS = {"head", "tail", "wc"}
SINK_ARG = re.compile(r"^(-\d+|-[ncl]|\d+)$")


def _help_segment(tokens):
    if not tokens or not NAME.match(tokens[0]) or tokens[0] in WRAPPERS:
        return False
    if os.path.splitext(tokens[0])[1] in SCRIPT_EXT:
        return False
    rest = tokens[1:]
    if rest and rest[-1] in HELP_FLAGS:
        rest = rest[:-1]
    elif rest and rest[0] == "help":
        rest = rest[1:]
    else:
        return False
    return all(WORD.match(t) for t in rest)


def _sink_segment(tokens):
    return bool(tokens) and tokens[0] in SINKS and all(SINK_ARG.match(t) for t in tokens[1:])


def _pipeline_ok(segment):
    stages = [s.split() for s in segment.split("|")]
    return _help_segment(stages[0]) and all(_sink_segment(s) for s in stages[1:])


def is_help_only(command):
    if not isinstance(command, str) or not command.strip():
        return False
    if UNSAFE.search(command) or "&" in SPLIT.sub(";", command):
        return False
    segments = [s for s in SPLIT.split(command) if s.strip()]
    return bool(segments) and all(_pipeline_ok(s) for s in segments)


ALLOW = [
    "tuios --help", "tuios -h", "mise --version", "rg -V", "git commit --help",
    "tuios send-text --help", "tuios ask-agent --help", "herdr pane run --help",
    "tuios help", "tuios help send-text",
    "tuios --help; mise --help", "tuios --help && mise run --help || rg --version",
    "tuios --help\nmise --help", "tuios --help | head -20", "tuios --help | wc -l",
]
DENY = [
    "", "   ", "tuios", "tuios list-agents", "tuios --help foo", "tuios -x --help",
    "tuios --help > out.txt", "tuios --help 2>&1", "tuios --help &",
    "tuios --help; rm -rf x", "tuios --help && rm x", "tuios --help | sh", "tuios --help | tee f",
    "tuios $(rm x) --help", "tuios `id` --help", "tuios 'a b' --help", "tuios \\send-text --help",
    "env rm --help", "xargs rm --help", "bash --help; sh -c x", "sh --help",
    "./run.sh --help", "/bin/rm --help", "run.sh --help", "deploy.py --help",
    "rm -rf --help x", "echo hi", "tuios -v",
]


def self_test():
    bad = [c for c in ALLOW if not is_help_only(c)] + [c for c in DENY if is_help_only(c)]
    for c in bad:
        print("FAIL help_only:", repr(c))
    print(f"help_only: {len(ALLOW)} allow, {len(DENY)} deny: {len(bad)} failed")
    return len(bad)
