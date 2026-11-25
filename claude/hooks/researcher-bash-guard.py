#!/usr/bin/env python3
"""PreToolUse hook for the researcher subagent: allow only find-docs' commands.

The researcher needs Bash for five things, and this hook blocks everything
else (exit 2, reason on stderr):

  read-page.sh -o <file> <https-url>       <file> inside a Claude temp dir
  context7.sh search|libs|context <k=v>... every further argument name=value
  exa.sh search|contents ... -o <file>     <file> inside a Claude temp dir; contents URLs https
  github.sh clone|api|search -o <out> ...  <out> inside a Claude temp dir
  rg <args>                                every path inside a Claude temp dir

A command must be one plain call: no $, backtick or newline anywhere, and no
unquoted operator (; & | < > ( )), so nothing can chain, redirect or expand.
"""

import json
import os
import re
import shlex
import sys

HOME = os.path.expanduser("~")
SKILL = os.path.join(HOME, ".claude/skills/find-docs")
READ_PAGE = os.path.realpath(os.path.join(SKILL, "read-page.sh"))
CONTEXT7 = os.path.realpath(os.path.join(SKILL, "context7.sh"))
EXA = os.path.realpath(os.path.join(SKILL, "exa.sh"))
GITHUB = os.path.realpath(os.path.join(SKILL, "github.sh"))

UID = os.getuid()
TEMP_ROOTS = {
    os.path.realpath(p)
    for p in (f"/tmp/claude-{UID}", os.environ.get("TMPDIR", ""))
    if p
}

ALLOWED = (
    "researcher may run only these Bash commands, each as one plain call:\n"
    "  ~/.claude/skills/find-docs/read-page.sh -o <scratchpad file> <https-url>\n"
    "  ~/.claude/skills/find-docs/context7.sh search|libs|context <name>=<value>...\n"
    "  ~/.claude/skills/find-docs/exa.sh search|contents ... -o <scratchpad file>\n"
    "  ~/.claude/skills/find-docs/github.sh clone|api|search -o <scratchpad path> ...\n"
    "  rg <args> <scratchpad path>"
)


def in_temp(path):
    real = os.path.realpath(os.path.expanduser(path))
    return any(real == r or real.startswith(r + os.sep) for r in TEMP_ROOTS)


def program(token):
    return os.path.realpath(os.path.expanduser(token))


def check(command):
    if re.search(r"[$`\n]", command):
        return "no $, backticks or newlines"
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError as e:
        return f"unparseable command ({e})"
    if not tokens:
        return "empty command"
    if any(set(t) <= set(";&|<>()") for t in tokens):
        return "no operators, pipes or redirects"

    prog, args = tokens[0], tokens[1:]
    if program(prog) == READ_PAGE:
        if len(args) == 3 and args[0] == "-o" and in_temp(args[1]) \
                and args[2].startswith("https://"):
            return None
        return "read-page.sh takes -o <scratchpad file> <https-url>"
    if program(prog) == CONTEXT7:
        if args and args[0] in ("search", "libs", "context") \
                and all("=" in a for a in args[1:]):
            return None
        return "context7.sh takes search|libs|context and <name>=<value> arguments"
    if program(prog) == EXA:
        out = [args[i + 1] for i, a in enumerate(args[:-1]) if a == "-o"]
        if args and args[0] in ("search", "contents") and len(out) == 1 and in_temp(out[0]):
            if args[0] == "search":
                return None
            urls = [a for a in args[1:] if not a.startswith("-") and a != out[0]
                    and not a.isdigit()]
            if urls and all(u.startswith("https://") for u in urls):
                return None
        return "exa.sh takes search|contents ... -o <scratchpad file>, contents URLs over https"
    if program(prog) == GITHUB:
        if len(args) >= 4 and args[0] in ("clone", "api", "search") \
                and args[1] == "-o" and in_temp(args[2]):
            return None
        return "github.sh takes clone|api|search -o <scratchpad path> ..."
    if prog == "rg":
        if any(a == "--pre" or a.startswith(("--pre=", "--pre-glob")) for a in args):
            return "rg --pre runs commands"
        paths = [a for a in args if a.startswith(("/", "~", "."))]
        if paths and all(in_temp(p) for p in paths):
            return None
        return "rg must search paths inside the scratchpad"
    return f"{prog} is not allowed"


def main():
    command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    reason = check(command)
    if reason:
        print(f"Blocked: {reason}.\n{ALLOWED}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
