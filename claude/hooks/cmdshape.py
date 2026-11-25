#!/usr/bin/env python3
"""Shell splitting shared by the Bash hooks.

decision_log.py reduces a command to its programs and flags, and a guard that
watches one program asks whether a command runs it. Both need the same thing: split
the text the way a shell would (quotes, ;, &&, ||, |, newlines), find the
program behind env, mise exec --, bash -c and the like, and refuse to guess
about anything dynamic.

  tokenize, pipelines   the splitting: stage token lists per ;/&&/|| segment
  unwrap                the guard's view: is this stage a call to one program?
  strip_wrappers        the recorder's view: the program behind env, time,
                        nice, nohup, mise exec --, fnox exec --, uv run, xargs
  command_segments      every simple command in a text, recursing into
                        bash -c, with redirects dropped and heredoc bodies cut

It reads and writes nothing; it never runs the command. Loaded by the hooks
with importlib, because python3 -I leaves the hooks directory off sys.path.

`python3 -I cmdshape.py --self-test` checks the cases below.
"""

import os
import re
import shlex
import sys

ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
OPERATOR = re.compile(r"^[();<>|&\n]+$")
SHELLS = {"bash", "sh", "zsh", "dash"}
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
# Programs that run another program from their arguments.
WRAPPERS = {
    "xargs", "sudo", "doas", "time", "nohup", "exec", "eval", "watch", "timeout", "nice",
    "setsid", "script", "ssh", "find", "parallel", "builtin", "chronic", "caffeinate",
}
BAD_ENV = ("PATH=", "LD_", "DYLD_")
MAX_DEPTH = 3

HEREDOC = re.compile(r"(<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2[^\n]*\n)(.*?)(^[ \t]*\3[ \t]*$)",
                     re.DOTALL | re.MULTILINE)


def tokenize(command):
    lex = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace_split = True
    lex.whitespace = " \t\r"
    lex.commenters = ""
    return list(lex)


def pipelines(command):
    """Return ([[stage token lists] per ;/&&/|| segment], odd) with odd set for
    redirects, subshells and background jobs."""
    result, stages, stage, odd = [], [], [], False
    for t in tokenize(command):
        if not OPERATOR.match(t):
            stage.append(t)
            continue
        op = t.replace("\n", "") or ";"
        if op == "|":
            stages.append(stage)
            stage = []
        elif op in (";", "&&", "||"):
            stages.append(stage)
            result.append(stages)
            stages, stage = [], []
        else:
            odd = True
            stages.append(stage)
            stage = []
    stages.append(stage)
    result.append(stages)
    return result, odd


def unwrap(tokens, target):
    """Return (kind, payload): target/args, shell/script, indirect/name, other/None.

    target is the program name looked for, such as "git"."""
    t = list(tokens)
    for _ in range(MAX_DEPTH + 3):
        while t and ASSIGN.match(t[0]):
            if t[0].startswith(BAD_ENV):
                return "indirect", t[0].split("=", 1)[0]
            t.pop(0)
        if not t:
            return "other", None
        name = os.path.basename(t[0])
        if name == target:
            return "target", t[1:]
        if name == "env":
            t = t[1:]
            while t and (t[0].startswith("-") or ASSIGN.match(t[0])):
                if t[0] in ("-S", "--split-string"):
                    return "indirect", "env -S"
                if ASSIGN.match(t[0]) and t[0].startswith(BAD_ENV):
                    return "indirect", t[0].split("=", 1)[0]
                t = t[2:] if t[0] in ("-u", "-C", "--unset", "--chdir") else t[1:]
            continue
        if name == "command" and len(t) > 1 and t[1] not in ("-v", "-V"):
            t = t[1:]
            continue
        if name == "mise" and len(t) > 1 and t[1] in ("exec", "x"):
            if "--" in t:
                t = t[t.index("--") + 1:]
                continue
            return ("indirect", "mise exec") if any(os.path.basename(a) == target for a in t) else ("other", None)
        if name == "fnox":
            # Global flags (-P profile, -c config) come before exec; the child starts after --.
            sub = next((i for i, a in enumerate(t[1:], 1) if a in ("exec", "x")), None)
            if sub is not None and "--" in t[sub:]:
                t = t[t.index("--", sub) + 1:]
                continue
            return ("indirect", "fnox exec") if any(os.path.basename(a) == target for a in t) else ("other", None)
        if name in SHELLS:
            for j, a in enumerate(t[1:], 1):
                if SHELL_C.match(a) and j + 1 < len(t):
                    return "shell", t[j + 1]
            return "other", None
        if name in WRAPPERS and any(os.path.basename(a) == target for a in t[1:]):
            return "indirect", name
        return "other", None
    return "indirect", "nested wrappers"


XARGS_VALUE = {"-I", "-n", "-P", "-d", "-L", "-E", "-s", "-a", "--max-args", "--max-procs", "--delimiter"}
UV_VALUE = {"--with", "--python", "-p", "--project", "--directory", "--env-file", "--group", "--extra",
            "--with-requirements", "--package", "--index", "--index-url"}


def strip_wrappers(tokens):
    """Return (argv, via, env): the program behind transparent wrappers.

    via names the wrappers that were removed, env holds NAME=value words (the
    leading ones and those of env). A wrapper that needs more care than this
    (sudo, timeout, ...) is not removed: it stays argv[0]."""
    t, via, env = list(tokens), [], []
    for _ in range(MAX_DEPTH + 3):
        while t and ASSIGN.match(t[0]):
            env.append(t.pop(0))
        if not t:
            break
        name = os.path.basename(t[0])
        if name == "env":
            t = t[1:]
            while t and (t[0].startswith("-") or ASSIGN.match(t[0])):
                if ASSIGN.match(t[0]):
                    env.append(t[0])
                    t = t[1:]
                else:
                    t = t[2:] if t[0] in ("-u", "-C", "--unset", "--chdir", "-S") else t[1:]
            via.append("env")
        elif name in ("command", "time", "nohup"):
            t = t[1:]
            while t and t[0].startswith("-") and name != "nohup":
                t = t[1:]
            via.append(name)
        elif name == "nice":
            t = t[1:]
            while t and t[0].startswith("-"):
                t = t[2:] if t[0] == "-n" else t[1:]
            via.append(name)
        elif name == "xargs":
            t = t[1:]
            while t and t[0].startswith("-"):
                t = t[2:] if t[0] in XARGS_VALUE else t[1:]
            via.append(name)
        elif name == "mise" and len(t) > 2 and t[1] in ("exec", "x") and "--" in t:
            t = t[t.index("--") + 1:]
            via.append("mise exec")
        elif name == "fnox" and "--" in t and any(a in ("exec", "x") for a in t[1:t.index("--")]):
            t = t[t.index("--") + 1:]
            via.append("fnox exec")
        elif name == "uv" and len(t) > 2 and t[1] == "run":
            t = t[2:]
            while t and t[0].startswith("-"):
                t = t[2:] if t[0] in UV_VALUE else t[1:]
            via.append("uv run")
        else:
            break
    return t, via, env


def strip_heredocs(command, marker=""):
    """Cut heredoc bodies (and the closing delimiter), keeping the << line."""
    return HEREDOC.sub(lambda m: m.group(1) + marker, command)


def command_segments(command, depth=0):
    """Return {"segments": [...], "odd": bool, "error": bool}.

    A segment is {"argv", "via", "env", "piped"}: one simple command with the
    wrappers of strip_wrappers removed. piped is true for every stage after
    the first of a pipeline. Redirect targets are dropped; shell -c payloads
    are split in turn down to MAX_DEPTH. odd is set for subshells, background
    jobs, command substitution and anything nested too deeply to follow."""
    out = {"segments": [], "odd": False, "error": False}
    command = strip_heredocs(command)
    try:
        tokens = tokenize(command)
    except ValueError:
        out["error"] = True
        return out
    if "`" in command or "$(" in command:
        out["odd"] = True
    stage, piped, skip = [], False, False

    def emit():
        argv, via, env = strip_wrappers(stage)
        if not argv:
            return
        if os.path.basename(argv[0]) in SHELLS:
            for j, a in enumerate(argv[1:], 1):
                if SHELL_C.match(a) and j + 1 < len(argv):
                    if depth >= MAX_DEPTH:
                        out["odd"] = True
                    else:
                        inner = command_segments(argv[j + 1], depth + 1)
                        out["segments"] += inner["segments"]
                        out["odd"] = out["odd"] or inner["odd"]
                        out["error"] = out["error"] or inner["error"]
                    return
        if os.path.basename(argv[0]) in ("eval", "exec"):
            out["odd"] = True
        out["segments"].append({"argv": argv, "via": via, "env": env, "piped": piped})

    for t in tokens:
        if skip:
            skip = False
            continue
        if not OPERATOR.match(t):
            stage.append(t)
            continue
        op = t.replace("\n", "") or ";"
        if op == "|":
            emit()
            stage, piped = [], True
        elif op in (";", "&&", "||"):
            emit()
            stage, piped = [], False
        elif set(op) <= set("<>&") and ("<" in op or ">" in op):
            if stage and stage[-1] in ("1", "2"):
                stage.pop()
            skip = True
        else:
            out["odd"] = True
            emit()
            stage, piped = [], False
    emit()
    return out


SEGMENT_CASES = [
    ("git push --force origin feat/x", [["git", "push", "--force", "origin", "feat/x"]]),
    ("cd ~/CX/foo && git push -f", [["cd", "~/CX/foo"], ["git", "push", "-f"]]),
    ("fnox exec -- aws s3 cp s3://bkt/k ./f", [["aws", "s3", "cp", "s3://bkt/k", "./f"]]),
    ("env FOO=1 time nice -n 5 nohup rg x", [["rg", "x"]]),
    ("mise exec node@22 -- npm run build", [["npm", "run", "build"]]),
    ("uv run --with rich python3 x.py", [["python3", "x.py"]]),
    ("ls | xargs -I{} wc -l {}", [["ls"], ["wc", "-l", "{}"]]),
    ("bash -c 'git pull; git push'", [["git", "pull"], ["git", "push"]]),
    ("sh -c \"bash -c 'ls | head -3'\"", [["ls"], ["head", "-3"]]),
    ("rg x 2>&1 | head -3 > out.txt", [["rg", "x"], ["head", "-3"]]),
    ("git commit -F - <<'EOF'\nfeat: a; rm -rf x\nEOF\ngit push", [["git", "commit", "-F", "-"], ["git", "push"]]),
    ("A=1 B=2 make test\nmake build", [["make", "test"], ["make", "build"]]),
]
ODD_CASES = ["(cd x && ls)", "sleep 1 &", "echo $(date)", "echo `date`", "eval ls",
             "bash -c 'bash -c \"bash -c \\\"bash -c ls\\\"\"'"]


def self_test():
    failures = 0

    def check(label, got, want):
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")

    for command, want in SEGMENT_CASES:
        got = command_segments(command)
        check(command, [s["argv"] for s in got["segments"]], want)
        check(command + " [not odd]", got["odd"] or got["error"], False)
    for command in ODD_CASES:
        check(command + " [odd]", command_segments(command)["odd"], True)
    check("unbalanced", command_segments("echo 'x")["error"], True)
    check("piped", [s["piped"] for s in command_segments("a | b; c")["segments"]], [False, True, False])
    check("via", command_segments("fnox exec -- env X=1 aws s3 ls")["segments"][0]["via"], ["fnox exec", "env"])
    check("env", command_segments("X=1 Y=2 make")["segments"][0]["env"], ["X=1", "Y=2"])
    check("heredoc", strip_heredocs("cat <<-X\nbody\n  X\nls"), "cat <<-X\n\nls")

    check("pipelines", pipelines("a && b | c; d"), ([[["a"]], [["b"], ["c"]], [["d"]]], False))
    check("pipelines odd", pipelines("a > f")[1], True)
    check("unwrap target", unwrap(["env", "A=1", "/bin/foo", "x"], "foo"), ("target", ["x"]))
    check("unwrap mise", unwrap(["mise", "exec", "--", "foo", "x"], "foo"), ("target", ["x"]))
    check("unwrap fnox", unwrap(["fnox", "exec", "--", "foo", "x"], "foo"), ("target", ["x"]))
    check("unwrap fnox profile", unwrap(["fnox", "-P", "slack", "x", "--no-defaults", "--", "foo"], "foo"), ("target", []))
    check("unwrap fnox no --", unwrap(["fnox", "exec", "foo", "x"], "foo"), ("indirect", "fnox exec"))
    check("via fnox profile", command_segments("fnox -P p exec --no-defaults -- rg x")["segments"][0]["via"], ["fnox exec"])
    check("unwrap shell", unwrap(["bash", "-lc", "foo x"], "foo"), ("shell", "foo x"))
    check("unwrap PATH", unwrap(["PATH=/x", "foo"], "foo"), ("indirect", "PATH"))
    check("unwrap xargs", unwrap(["xargs", "foo"], "foo"), ("indirect", "xargs"))
    check("unwrap other", unwrap(["ls"], "foo"), ("other", None))
    print(f"cmdshape: {len(SEGMENT_CASES)} segment, {len(ODD_CASES)} odd cases: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else 2)
