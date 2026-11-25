"""Shared checks: is a Bash command nothing but help or version queries?

Used by help-allow.py, which auto-allows such commands, and by
pane-control-guard.py, which does not ask about them.

A segment passes only when it is a bare command name, then subcommand-like
words, then exactly one help flag (--help, -h, --version, -V), or `help` as
the first argument. Segments may be joined by ;, && or || and may pipe into
head, tail or wc. Any quote, expansion, redirect, glob, backslash or background
`&` rejects the whole command, as do wrappers that run another program (env,
xargs, sudo, ...) and names with a script extension (`run.sh --help` runs a
script from PATH that may ignore the flag).

is_reference_query accepts the same commands plus the form agent CLIs use to
print their own usage guide: `<cmd> [subwords] --skill [name]`, with nothing
after the optional name. A bare `skill` word is not one: in `rm skill` it is an
argument.
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


def _reference_segment(tokens):
    if not tokens or not NAME.match(tokens[0]) or tokens[0] in WRAPPERS:
        return False
    if os.path.splitext(tokens[0])[1] in SCRIPT_EXT:
        return False
    rest = tokens[1:]
    for i, token in enumerate(rest):
        # Only the flag: a bare "skill" word is an argument to most programs (rm skill, git commit skill).
        if token == "--skill":
            before, after = rest[:i], rest[i + 1:]
            return all(WORD.match(t) for t in before) and len(after) <= 1 and all(WORD.match(t) for t in after)
        if not WORD.match(token):
            return False
    return False


def _sink_segment(tokens):
    return bool(tokens) and tokens[0] in SINKS and all(SINK_ARG.match(t) for t in tokens[1:])


def _pipeline_ok(segment, reference=False):
    stages = [s.split() for s in segment.split("|")]
    head = _help_segment(stages[0]) or (reference and _reference_segment(stages[0]))
    return head and all(_sink_segment(s) for s in stages[1:])


def _all_segments_ok(command, reference):
    if not isinstance(command, str) or not command.strip():
        return False
    if UNSAFE.search(command) or "&" in SPLIT.sub(";", command):
        return False
    segments = [s for s in SPLIT.split(command) if s.strip()]
    return bool(segments) and all(_pipeline_ok(s, reference) for s in segments)


def is_help_only(command):
    return _all_segments_ok(command, False)


def is_reference_query(command):
    """True when every segment is help-only or a --skill / skill query."""
    return _all_segments_ok(command, True)


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


REFERENCE_ALLOW = [
    "twg --skill", "twg --skill jira", "tuios --skill tml", "twg jira --skill",
    "mise --version; twg --skill", "twg --skill | head -50", "tuios --skill\nmise --help",
    "tuios --skill && tuios --skill tml",
]
REFERENCE_DENY = [
    "foo skill install x", "twg skill install x", "twg --skill jira x", "twg --skill -x", "twg skill 'a b'",
    "twg --skill > out", "twg --skill; rm x", "twg --skill | sh", "twg --skill $(id)", "twg -x --skill",
    "twg --skill=jira", "twg skills", "skill", "--skill", "env twg --skill", "sudo twg skill", "bash --skill",
    "./run.sh skill", "run.sh --skill", "deploy.py skill", "twg skill &", "twg skill\\x", "twg x/y skill",
    "twg skill ~", "twg skill jira/x", "twg skill 1", "twg skill 'x'", "twg --skill --help x",
    "twg skill", "twg skill jira", "twg skill install", "rm skill", "git commit skill",
    "twg jira workitem skill create", "tuios skill tml",
]


def self_test():
    bad = [c for c in ALLOW if not is_help_only(c)] + [c for c in DENY if is_help_only(c)]
    bad += [c for c in ALLOW + REFERENCE_ALLOW if not is_reference_query(c)]
    bad += [c for c in DENY + REFERENCE_DENY if is_reference_query(c)]
    for c in bad:
        print("FAIL help_only:", repr(c))
    print(f"help_only: {len(ALLOW)} allow, {len(DENY)} deny, {len(REFERENCE_ALLOW)} reference allow, "
          f"{len(REFERENCE_DENY)} reference deny: {len(bad)} failed")
    return len(bad)
