#!/usr/bin/env python3
"""PreToolUse hook for Bash: deny interpreter code passed inline.

`python3 -c "..."`, `python3 - <<'EOF'`, `perl -e`, `node -e` and their
kin put a program inside a command string. The permission prompt shows it
as one long line, atuin stores it truncated, and a file edit made that way
has no diff. Each use has a reviewable replacement, which the deny reason
names: jq or nu for structured data, the Edit tool or sd for file edits,
and a script file for real logic.

Running a script file stays allowed (`python3 -I tool.py`, `node x.mjs`),
as do module runs (`python3 -m json.tool`, `python3 -m pytest`) and
`--version`. Heredocs that feed something other than an interpreter
(`cat > f <<EOF`, `git commit -F - <<EOF`) are not touched, and their
bodies are not searched.

The command is split on shell operators with quoting respected, so
`git commit -m "... python3 -c ..."` passes while `bash -c 'python3 -c x'`
does not. A command at the start of a segment counts, and so does one behind
env, time, nice, nohup, sudo, xargs, uv run or mise exec.

It fails open: an error lets the command through, since this guard steers
habits and is not a security boundary (the sandbox is).

`python3 inline-script-guard.py --self-test` checks the tables below.
"""

import json
import re
import shlex
import sys

PYTHON = re.compile(r"^(python[\d.]*|pypy[\d.]*)$")
SHELLS = {"sh", "bash", "zsh", "fish", "dash"}
WRAPPERS = {"env", "time", "nice", "nohup", "sudo", "xargs", "uv", "uvx", "mise", "exec"}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n", "|&", ";;"}
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][\w-]*)\1")


def strip_heredoc_bodies(command):
    """Drop heredoc bodies, keeping the line that opens each one."""
    out, lines, i = [], command.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        markers = [m.group(2) for m in HEREDOC.finditer(line)]
        i += 1
        for marker in markers:
            while i < len(lines) and lines[i].strip() != marker:
                i += 1
            i += 1
    return "\n".join(out)


def tokens(text):
    lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = False
    try:
        return list(lexer)
    except ValueError:
        return text.split()


def segments(text):
    seg = []
    for tok in tokens(text):
        if tok in SEPARATORS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(tok)
    if seg:
        yield seg


def program_name(token):
    return token.rsplit("/", 1)[-1]


def python_inline(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-", "<<", "<<-", "<<<"):
            return "python program from stdin"
        if a in ("--version", "-V", "--help", "-h"):
            return None
        if a.startswith("--"):
            i += 1
            continue
        if a.startswith("-"):
            for j, ch in enumerate(a[1:], 1):
                if ch == "c":
                    return "python -c"
                if ch == "m":
                    return None
                if ch in "WX":
                    if j == len(a) - 1:
                        i += 1
                    break
            i += 1
            continue
        if a.startswith("<"):
            return "python program from stdin" if a.startswith("<<") else None
        return None
    return "python program from stdin"


def eflag_inline(prog, args):
    for i, a in enumerate(args):
        if a in ("-", "<<", "<<-", "<<<"):
            return f"{prog} program from stdin"
        if a.startswith("--"):
            if a in ("--eval", "--print") or a.startswith(("--eval=", "--print=")):
                return f"{prog} {a.split('=')[0]}"
            if a in ("--version", "--help"):
                return None
            continue
        if a.startswith("-"):
            flags = a[1:]
            if prog in ("perl", "ruby") and any(c in flags for c in "eE"):
                return f"{prog} -e"
            if prog in ("node", "bun") and flags[:1] in ("e", "p"):
                return f"{prog} -{flags[:1]}"
            if prog == "php" and "r" in flags:
                return "php -r"
            continue
        if prog == "deno" and i == 0:
            return "deno eval" if a == "eval" else None
        return None
    return f"{prog} program from stdin" if prog in ("perl", "ruby", "node", "php") else None


def classify(prog, args):
    if PYTHON.match(prog):
        return python_inline(args)
    if prog in ("perl", "ruby", "node", "bun", "deno", "php"):
        return eflag_inline(prog, args)
    return None


def hits_in(text, depth=0):
    found = []
    for seg in segments(strip_heredoc_bodies(text)):
        while seg and re.match(r"^[A-Za-z_]\w*=", seg[0]):
            seg = seg[1:]
        if not seg:
            continue
        head = program_name(seg[0])
        start = None
        if head in WRAPPERS:
            for k, tok in enumerate(seg[1:9], 1):
                if classify(program_name(tok), []) is not None or program_name(tok) in ("bun", "deno"):
                    start = k
                    break
        elif head in SHELLS and depth < 3:
            for k, tok in enumerate(seg[:-1]):
                if tok == "-c" or (tok.startswith("-") and not tok.startswith("--") and tok.endswith("c")):
                    found += hits_in(seg[k + 1], depth + 1)
                    break
        else:
            start = 0
        if start is not None:
            hit = classify(program_name(seg[start]), seg[start + 1:])
            if hit and hit not in found:
                found.append(hit)
        for tok in seg:
            if "$(" in tok and depth < 3:
                found += hits_in(tok.split("$(", 1)[1], depth + 1)
    return found


def advice(command):
    lowered = command.lower()
    first = []
    if "json" in lowered:
        first.append("For JSON, use `jq` for paths and filters, or `nu -c 'open f.json | ...'` "
                     "for tables, grouping and joins. Save large output to a scratchpad file first "
                     "and look at its shape (`jq 'keys'`) before extracting.")
    if re.search(r"\.write\(|write_text\(|\.replace\(", command):
        first.append("For file edits, use the Edit tool (it shows a diff), `sd` for "
                     "find-and-replace, or `ast-grep -U` for structural rewrites.")
    rest = ("Otherwise use a dedicated CLI (jq, nu, sd, rg, ast-grep), or, for real logic, "
            "write a script file to the scratchpad with the Write tool and run it by path "
            "(`python3 -I <path>`).")
    return " ".join(first + [rest])


def evaluate(command):
    hits = hits_in(command)
    if not hits:
        return None
    return (f"Inline interpreter code is not allowed ({', '.join(hits)}): it can't be reviewed "
            f"in a permission prompt and clutters shell history. {advice(command)}")


def main():
    if "--self-test" in sys.argv:
        return self_test()
    try:
        data = json.load(sys.stdin)
        if data.get("tool_name") != "Bash":
            return 0
        command = (data.get("tool_input") or {}).get("command")
        why = evaluate(command) if isinstance(command, str) and command else None
    except Exception:
        return 0
    if why:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": why,
        }}))
    return 0


DENY = [
    "python3 -c 'import json; print(1)'",
    "python -c 'print(1)'",
    "/usr/bin/python3 -c x",
    "python3.12 -c x",
    "python3 -I -c 'import json'",
    "python3 -Ic 'import json'",
    "python3 -W ignore -c x",
    "python3 - <<'EOF'\nimport json\nEOF",
    "python3 <<EOF\nprint(1)\nEOF",
    "cd ~/x && python3 - <<'EOF'\ns=open('f').read()\nEOF",
    "tuios list-windows --json | python3 -c 'import json,sys'",
    "echo 'print(1)' | python3",
    "uv run --with pandas python -c 'import pandas'",
    "env FOO=1 python3 -c x",
    "FOO=1 python3 -c x",
    "mise exec -- python3 -c x",
    "bash -c 'cd x; python3 -c \"print(1)\"'",
    "sh -lc 'python3 -c x'",
    "echo $(python3 -c 'print(1)')",
    "perl -pi -e 's/a/b/' f",
    "perl -ne 'print' f",
    "ruby -e 'puts 1'",
    "node -e 'console.log(1)'",
    "node --eval 'x'",
    "node -p 'process.version'",
    "cat x.js | node",
    "bun -e 'x'",
    "deno eval 'x'",
    "php -r 'echo 1;'",
]
PASS = [
    "python3 tool.py --flag",
    "python3 -I \"$HOME/.claude/hooks/pane-control-guard.py\"",
    "python3 -m json.tool f.json",
    "python3 -m pytest -q",
    "python3 --version",
    "python3 -V",
    "TUIOS_PLUGIN_EVENT=x python3 jumplist.py event",
    "node scripts/build.mjs",
    "perl script.pl",
    "bun run test",
    "deno run x.ts",
    "jq -r '.foo' f.json",
    "nu -c 'open f.json | get foo'",
    "git commit -m 'stop using python3 -c for json'",
    "git commit -F - <<'EOF'\nfix: python3 -c was used here\nEOF",
    "cat > notes.md <<'EOF'\nRun python3 -c 'x' to test\nEOF",
    "rg -n 'python3 -c' ~/dotfiles",
    "command -v python3 jq nu",
    "which python3",
    "awk '{print $1}' f",
    "sd 'a' 'b' f",
]


def self_test():
    failures = 0
    for command in DENY:
        if not evaluate(command):
            failures += 1
            print(f"FAIL should deny: {command!r}")
    for command in PASS:
        got = evaluate(command)
        if got:
            failures += 1
            print(f"FAIL should pass: {command!r}: {got[:80]}")
    json_reason = evaluate("python3 -c 'import json'") or ""
    if "jq" not in json_reason:
        failures += 1
        print("FAIL json advice missing")
    edit_reason = evaluate("python3 - <<'EOF'\ns=open(p).read(); open(p,'w').write(s)\nEOF") or ""
    if "Edit tool" not in edit_reason:
        failures += 1
        print("FAIL edit advice missing for a heredoc that writes a file")
    print(f"{len(DENY)} deny, {len(PASS)} pass: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
