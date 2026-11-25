#!/usr/bin/env python3
"""PreToolUse hook for Bash and the tuios MCP tools: ask before commands that
read from a pane, type into a shell, launch panes or agents, close or kill
them, or change grants, config, plugins or code.

Those commands let an agent drive other terminals and agents on its own, so
each one gets a prompt in every permission mode, auto mode included: a hook's
"ask" is shown even where an allow rule or the classifier would have approved
the call. This hook is the only gate: settings.json holds no ask rules for
tuios or herdr, because a rule matches the command text from its start
(`tuios -s x send-text` slips past `Bash(tuios send-text *)`) and cannot carve
out `--help`. It is registered with onFailure "block", so a crash or timeout
blocks the call instead of letting it through.

Asking an agent is allowed: `tuios ask-agent`, `tuios queue`, `tuios review
send` and mail type a prompt into an agent whose own permissions still apply.
`ask-agent` still asks with --allow-blocked (that answers a permission
prompt), --force, or --select with --yes or --confirm (many agents at once,
unlisted). `respond` always asks: it approves other agents' prompts.

The command text is searched for herdr/tuios invocations wherever they sit:
after `&&` or `;`, behind a path, `env`, `xargs` or `mise exec --`, inside
`bash -c '...'`, `$(...)` or a heredoc, and again with quotes and backslashes
removed (`\tuios`, `tuio''s`). Text that only becomes data is skipped: a
git `-m`/`--message` value in single quotes (or double quotes with no `$` or
backtick), and the body of a heredoc read by a text consumer such as `git`,
`cat` or `tee` when nothing on its line pipes it on or runs a shell. A heredoc
fed to `bash`, piped onward, or on a line that runs an interpreter is still
searched. Script files named on the command line (.sh,
.py, ...) are searched too, one level deep. Commands that are only help or
version queries (help_only.py) are never asked about.

A `tuios split-window` or `new-window` whose pane only shows files passes
(pagers, log viewers, nvim -R):
tuios flags from LAUNCH_FLAGS, then `--` and a bare viewer from VIEWERS with
only that viewer's listed flags. Flags that change what the pane may do
(--host, --grants, --kind, --wait) and viewer flags that run commands (less
`+!cmd`, bat --pager) still ask.

An agent launch typed directly (`tuios start-agent`, `delegate`, `fan`, and
the MCP `delegate` and `fan` tools) without `--grants` is denied, not asked:
under `[agents.permissions] mode = "open"` the new agent would inherit this
pane's `admin`. The reason tells the agent to pass `--grants read,write,task`
(or `read`). `delegate --role review|research` passes, since tuios gives those
`read` by default. Launches inside script files are only asked about, because
a script's flags can sit on continued lines this scan does not join.

`tuios ship push` and `ship pr` are denied too: pushing stays with the user,
so the agent prints the command instead. `ship merge` still asks.

It errs towards asking. Not covered: a program that talks to the herdr or
tuios socket directly, and commands assembled at run time (`$cmd` is asked
about, a string built in a script's own variables is not).

`python3 -I pane-control-guard.py --self-test` checks the tables below.
"""

import importlib.util
import json
import os
import re
import shlex
import sys

READ, TYPE, LAUNCH, DESTROY, ADMIN = "read", "type", "launch", "destroy", "admin"
AGENT = "agent"
WHAT = {
    READ: "reads pane output",
    TYPE: "types into a pane or answers an agent's prompt",
    LAUNCH: "launches a pane, tab, workspace, agent or plugin",
    DESTROY: "closes, moves or kills panes, sessions or the server",
    ADMIN: "changes grants, config, a work tree or ships code",
    AGENT: "asks an agent with a flag that skips tuios's safeguards",
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
    ("pane", "close"): DESTROY,
    ("pane", "move"): DESTROY,
    ("tab", "close"): DESTROY,
    ("workspace", "close"): DESTROY,
    ("server", "stop"): DESTROY,
    ("server", "reload-config"): DESTROY,
}

# Top-level subcommands from `tuios --help`; a dict maps the second word, "*"
# for any. `call`, `run-command`, `tape`, `tmux`, `tmux-shim` and `mcp` can
# issue any of the others, so they count as typing.
TUIOS = {
    "capture-pane": READ,
    "pane-view": READ,
    "screenshot": READ,
    "agent-log": READ,
    "peek-prompt": READ,
    "explain-agent-detect": READ,
    "explain-agent-screen": READ,
    "subscribe": READ,
    "record-pane": {"start": READ},
    "run": TYPE,
    "send-text": TYPE,
    "send-keys": TYPE,
    "paste-buffer": TYPE,
    "respond": TYPE,
    "resume-agent": TYPE,
    "call": TYPE,
    "run-command": TYPE,
    "tape": TYPE,
    "tmux": TYPE,
    "tmux-shim": TYPE,
    "mcp": TYPE,
    "task": {"add": TYPE, "dispatch": LAUNCH},
    "ask-agent": AGENT,
    "new-window": LAUNCH,
    "split-window": LAUNCH,
    "start-agent": LAUNCH,
    "delegate": LAUNCH,
    "agent-proto": LAUNCH,
    "fan": LAUNCH,
    "popup": LAUNCH,
    "xpanes": LAUNCH,
    "new": LAUNCH,
    "worktree": LAUNCH,
    "resurrect": LAUNCH,
    "plugins": dict.fromkeys(
        ["run", "open", "dev", "build", "install", "update", "enable", "approve", "link"], LAUNCH),
    "close-window": DESTROY,
    "close-workspace": DESTROY,
    "kill-session": DESTROY,
    "kill-server": DESTROY,
    "restart-server": DESTROY,
    "detach-client": DESTROY,
    "set-pane-grants": ADMIN,
    "set-config": ADMIN,
    "checkpoint": {"restore": ADMIN},
    "ship": {"commit": ADMIN, "merge": ADMIN, "push": ADMIN, "pr": ADMIN},
}

VIEW_LAUNCH = {"split-window", "new-window"}
LAUNCH_FLAGS = {
    "-s", "--session", "-w", "--window", "--cwd", "--name", "--ratio", "--workspace",
    "--no-focus", "--keep-open", "--json", "--print-id",
}
VIEWERS = {
    "leaf": {"-w", "--watch"},
    "less": {"-R", "-r", "-S", "-N", "-F", "-X", "-K", "+F", "+G"},
    "more": set(),
    "bat": {"-p", "-pp", "--plain", "-n", "--number", "-A", "--show-all", "-l", "--language", "--paging"},
    "cat": {"-n", "-v", "-A", "-e", "-t"},
    "glow": {"-p", "--pager", "-w", "--width", "-s", "--style"},
    "tail": {"-f", "-F", "-n"},
    "head": {"-n"},
    "mdcat": {"-p", "--paginate", "-l", "--local", "--columns"},
    "moor": set(),
    "csvlens": {"-d", "--delimiter", "-t", "-c", "--no-headers", "--columns", "--filter", "--find",
                "-i", "--ignore-case", "-S", "-W", "--wrap", "--auto-reload", "--color-columns"},
    # Not tspin -e/--exec or --pager, not lnav -c/-f/-e/-i/-m/-u/-I/-d: they run commands.
    "tspin": {"-f", "--follow", "--highlight", "--enable", "--disable", "--extras"},
    "lnav": {"-r", "-R", "-q", "-N", "-t"},
    "hl": {"-s", "--sort", "-F", "--follow", "--tail", "-l", "--level", "--since", "--until",
           "-f", "--filter", "-q", "--query", "-L", "--local", "-e", "-E", "-c", "-P", "--paging"},
    # No -c, --cmd, +cmd, -S, -u, -l or --listen: each runs Vim script or Lua.
    "nvim": {"-R", "-M", "-n"},
    "view": {"-R", "-M", "-n"},
    # Not --ai-*, --k8s-*, --otlp-*, --vmlogs-*, --web-port or --config: they send
    # logs out, open listeners or read clusters.
    "gonzo": {"-f", "--file", "--follow", "--format", "-s", "--skin", "--disable-version-check",
              "-b", "--log-buffer", "-m", "--memory-size", "-u", "--update-interval",
              "--use-log-time", "--reverse-scroll-wheel", "--stop-words", "--web-disabled"},
    "fx": {"-r", "--raw", "-s", "--slurp", "--yaml", "--toml", "--edn", "--maml", "--xml",
           "--html", "--strict", "--no-inline"},
    # Not --debug (writes a file) or --config.
    "otree": {"-t", "--content-type", "-o", "--to", "--disable-header", "--disable-footer",
              "--disable-filter", "--tree-disable-selected-highlight", "--tree-selected-symbol",
              "--tree-format", "--filter-ignore-case", "--filter-exclude-mode", "-f",
              "--header-format", "-V", "--vertical", "-H", "--horizontal", "-s", "--size",
              "--disable-highlight", "-w", "--wrap", "--ignore-config", "--max-data-size",
              "-R", "--live-reload"},
}
# fx reads every argument after the file as JavaScript, whose save() writes the file.
MAX_PATHS = {"fx": 1}
# Viewers that are only viewers with one of these flags.
VIEWER_NEEDS = {"nvim": {"-R", "-M"}}
# lnav opens host:path over ssh and runs a helper there.
NO_REMOTE = {"lnav"}

# Options that come before the subcommand and take a value. An unknown option
# might take one too, so the word after it is checked as a subcommand as well.
VALUE_OPTS = {
    "herdr": {"--session", "--machine", "--remote"},
    "tuios": {
        "-s", "--session", "-w", "--window", "--server", "--theme", "--cpuprofile",
        "--pprof", "--border-style", "--dockbar-position", "--scrollback-lines",
        "--window-button-position", "--window-button-style", "--window-title-position",
        "--zoom-max-width",
    },
}
# Options that print something and exit before any subcommand runs.
EXIT_OPTS = {
    "herdr": {"--help", "-h", "--version", "-V"},
    "tuios": {"--help", "-h", "--version", "-v", "--skill", "--list-themes", "--preview-theme"},
}
KNOWN_FLAGS = {
    "herdr": set(),
    "tuios": {"--debug", "--ascii-only", "--no-animations", "--standalone", "--json",
              "--confirm-quit", "--hide-clock", "--show-clock", "--hide-scrollbar",
              "--hide-window-buttons", "--shared-borders", "--show-cpu", "--show-ram",
              "--show-keys"},
}

# The program name at a command position or inside a quoted string, not a
# longer word: herdr-agent-state.sh and ~/.config/herdr/ do not match.
CALL = re.compile(r"""(?:^|[\s;&|(`'"=/])(herdr|tuios)(?=[\s'")`;&|]|$)""")
# Where an invocation's own arguments end.
BOUNDARY = re.compile(r"[;&|)\n`]|\$\(")
UNQUOTE = re.compile(r"""[\\'"]""")
SCRIPT_EXT = {".sh", ".bash", ".zsh", ".fish", ".py", ".js", ".mjs", ".ts", ".rb", ".pl", ".lua"}
MAX_SCRIPT_BYTES = 256 * 1024
MAX_SCRIPTS = 8
UNKNOWN = "unknown"

MCP_PREFIX = "mcp__tuios__tuios_"
MCP_PASS = {
    "list_agents", "list_windows", "get_agent_state", "wait_for", "read_agent_messages",
    "send_agent_message", "set_agent_state", "set_agent_meta", "ask_agent",
}
MCP_ASK = {
    "capture_pane": READ,
    "peek_prompt": READ,
    "events": READ,
    "send_text": TYPE,
    "send_keys": TYPE,
    "respond": TYPE,
    "fan": LAUNCH,
    "delegate": LAUNCH,
}


USER_SHIPS = {"push", "pr"}
USER_SHIP = (
    "Pane control: `tuios ship {sub}` sends work off this machine, and pushing is the "
    "user's. Print the command for the user to run instead; do not run it."
)

AGENT_LAUNCHES = {"start-agent", "delegate", "fan"}
READ_ROLES = {"review", "research"}
UNGRANTED = (
    "Pane control: `{name}` starts an agent without `--grants`, so it would get this "
    "pane's own grants (admin while tuios runs in open mode). Pass `--grants "
    "read,write,task` for a worker, or `--grants read` for a read-only job; name wider "
    "grants only when the user asked for them."
)


def own_args(args):
    return args[:args.index("--")] if "--" in args else args


def flag_value(args, flag):
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a.split("=", 1)[1]
    return None


def ungranted(prog, args):
    """The launch's name when it starts an agent without narrowed grants."""
    if prog != "tuios":
        return None
    hit = classify(prog, args)
    if not hit or hit[1] != LAUNCH:
        return None
    sub = hit[0].split()[1]
    if sub not in AGENT_LAUNCHES:
        return None
    own = own_args(args)
    if flag_value(own, "--grants") is not None:
        return None
    if sub == "delegate" and flag_value(own, "--role") in READ_ROLES:
        return None
    return hit[0]


def deny_reason(command):
    if is_help_only(command):
        return None
    for variant in variants(command):
        for prog, args in invocations(variant):
            hit = classify(prog, args)
            if hit and hit[0] in {f"tuios ship {s}" for s in USER_SHIPS}:
                return USER_SHIP.format(sub=hit[0].split()[2])
            name = ungranted(prog, args)
            if name:
                return UNGRANTED.format(name=name)
    return None


def load_help_only():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "help_only.py")
    spec = importlib.util.spec_from_file_location("help_only", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    help_only = load_help_only()
    is_help_only = help_only.is_help_only
except Exception:  # without it, nothing counts as a help query: more asking, never less
    help_only = None

    def is_help_only(command):
        return False


HEREDOC = re.compile(r"(?<!<)<<(-?)[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
# A heredoc read by one of these is data, unless its line also runs something.
TEXT_CONSUMERS = {
    "git", "cat", "tee", "jq", "yq", "sd", "rg", "wc", "printf", "echo", "pbcopy",
    "glow", "leaf", "less", "bat",
}
RUNS_CODE = re.compile(
    r"\b(bash|sh|zsh|fish|dash|ksh|eval|source|python3?|node|perl|ruby|tuios|herdr|xargs)\b")
SEGMENT_START = re.compile(r"[;&|\n(`]|\$\(")
GIT_MESSAGE = re.compile(
    r"""(\bgit\b[^;&|\n]*?\s(?:-[A-Za-z]*m|--message)(?:=|\s+))('[^']*'|"(?:[^"\\$`]|\\.)*")""")


def inert_heredoc(line, pos):
    before, after = line[:pos], line[pos:]
    words = SEGMENT_START.split(before)[-1].split()
    if not words or os.path.basename(words[0]) not in TEXT_CONSUMERS:
        return False
    return "|" not in after and not RUNS_CODE.search(before) and not RUNS_CODE.search(after)


def strip_heredocs(text):
    lines, out, i = text.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        for m in HEREDOC.finditer(line):
            dash, delim = m.group(1), m.group(3)
            body = []
            while i < len(lines):
                current = lines[i]
                i += 1
                if (current.lstrip("\t") if dash else current) == delim:
                    break
                body.append(current)
            if not inert_heredoc(line, m.start()):
                out.extend(body)
            out.append(delim)
    return "\n".join(out)


def strip_messages(text):
    while True:
        stripped = GIT_MESSAGE.sub(lambda m: m.group(1) + "_", text)
        if stripped == text:
            return text
        text = stripped


def searchable(text):
    return strip_messages(strip_heredocs(text))


def variants(text):
    clean = searchable(text)
    return (clean, UNQUOTE.sub("", clean))


def invocations(text):
    for m in CALL.finditer(text):
        tail = BOUNDARY.split(text[m.end():m.end() + 400], 1)[0]
        try:
            args = shlex.split(tail)
        except ValueError:
            args = tail.split()
        yield m.group(1), args


def agent_flags_risky(args):
    flags = set(a.split("=", 1)[0] for a in args)
    if "--allow-blocked" in flags or "--force" in flags:
        return True
    return "--select" in flags and bool(flags & {"--yes", "--confirm"})


def lookup(prog, rest, args):
    if prog == "herdr":
        return HERDR.get(tuple(rest[:2]))
    entry = TUIOS.get(rest[0])
    if isinstance(entry, dict):
        sub = rest[1] if len(rest) > 1 else None
        return entry.get(sub, entry.get("*")) if sub else None
    if entry == AGENT:
        return AGENT if agent_flags_risky(args) else None
    return entry


def viewer_launch(rest):
    if rest[0] not in VIEW_LAUNCH or "--" not in rest:
        return False
    cut = rest.index("--")
    own, cmd = rest[1:cut], rest[cut + 1:]
    if any(w.startswith("-") and w.split("=", 1)[0] not in LAUNCH_FLAGS for w in own):
        return False
    if not cmd or cmd[0] not in VIEWERS:
        return False
    prog, argv = cmd[0], cmd[1:]
    if prog in VIEWER_NEEDS and not VIEWER_NEEDS[prog] & set(argv):
        return False
    if prog in NO_REMOTE and any(":" in a for a in argv):
        return False
    if prog in MAX_PATHS and sum(not a.startswith("-") for a in argv) > MAX_PATHS[prog]:
        return False
    return all(a.split("=", 1)[0] in VIEWERS[prog] for a in argv if a.startswith(("-", "+")))


def classify(prog, args):
    """Return (name, kind) for a sensitive invocation, else None."""
    if "--" in args:
        own = args[:args.index("--")]
    else:
        own = args
    if prog == "tuios" and ("--help" in own or "-h" in own):
        return None  # cobra prints help wherever the flag sits before --
    opts, exits, known = VALUE_OPTS[prog], EXIT_OPTS[prog], KNOWN_FLAGS[prog]
    i, unsure = 0, False
    while i < len(args) and args[i].startswith("-") and args[i] != "--":
        flag = args[i].split("=", 1)[0]
        if flag in exits:
            return None
        if "=" in args[i] or flag in known:
            i += 1
        elif flag in opts:
            i += 2
        else:
            unsure = True
            i += 1
    rest = args[i:]
    if not rest:
        return None
    n = 2 if prog == "herdr" else 1
    words = rest[:n]
    if any(w.startswith(("$", "<")) for w in words):
        return (f"{prog} {' '.join(words)}", UNKNOWN)
    kind = lookup(prog, rest, args)
    if not kind and unsure and len(rest) > 1:
        rest, words = rest[1:], rest[1:1 + n]
        kind = lookup(prog, rest, args)
    if not kind:
        return None
    if kind == LAUNCH and prog == "tuios" and viewer_launch(rest):
        return None
    if isinstance(TUIOS.get(rest[0]), dict) and prog == "tuios" and len(rest) > 1:
        words = rest[:2]
    return (f"{prog} {' '.join(words)}", kind)


def hits_in(text):
    found = []
    for variant in variants(text):
        for prog, args in invocations(variant):
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
    if is_help_only(command):
        return None
    direct = hits_in(command)
    scripts = script_hits(command, cwd)
    return reason(direct, scripts) if direct or scripts else None


def deny_mcp(tool, params):
    name = tool[len(MCP_PREFIX):] if tool.startswith(MCP_PREFIX) else tool
    if name not in {"delegate", "fan"} or params.get("grants"):
        return None
    if name == "delegate" and params.get("role") in READ_ROLES:
        return None
    return UNGRANTED.format(name=tool)


def evaluate_mcp(tool, params):
    name = tool[len(MCP_PREFIX):] if tool.startswith(MCP_PREFIX) else tool
    if name == "ask_agent":
        risky = params.get("allow_blocked") or params.get("force") or (
            params.get("select") and params.get("confirm"))
        return f"Pane control: `{tool}` {WHAT[AGENT]}." if risky else None
    if name in MCP_PASS:
        return None
    if name in MCP_ASK:
        return f"Pane control: `{tool}` {WHAT[MCP_ASK[name]]}."
    return f"Pane control: `{tool}` is a tuios tool this guard does not know yet, so it asks."


def main():
    if "--self-test" in sys.argv:
        return self_test()
    data = json.load(sys.stdin)
    tool = data.get("tool_name") or ""
    params = data.get("tool_input") or {}
    decision, why = "ask", None
    try:
        if tool == "Bash":
            command = params.get("command")
            if isinstance(command, str) and command:
                denied = deny_reason(command)
                if denied:
                    decision, why = "deny", denied
                else:
                    why = evaluate(command, data.get("cwd"))
        elif tool.startswith("mcp__tuios__"):
            denied = deny_mcp(tool, params)
            if denied:
                decision, why = "deny", denied
            else:
                why = evaluate_mcp(tool, params)
    except Exception as e:  # a broken guard asks rather than waves through
        decision, why = "ask", f"pane-control-guard failed ({type(e).__name__}: {e}); asking instead"
    if why:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
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
    ("herdr --machine m pane run p ls", TYPE),
    ("herdr pane close p", DESTROY),
    ("herdr server stop", DESTROY),
    ("tuios send-text -s dotfiles -w build 'ls'", TYPE),
    ("tuios -s x capture-pane -w y", READ),
    ('tuios new-window -s "$TUIOS_SESSION" slides --no-focus -- ls', LAUNCH),
    ("tuios split-window -s s right --no-focus -- make test", LAUNCH),
    ("tuios split-window right -- leaf --update", LAUNCH),
    ("tuios split-window right -- less +!rm x", LAUNCH),
    ("tuios split-window right -- bat --pager sh f", LAUNCH),
    ("tuios split-window right -- ./leaf f.md", LAUNCH),
    ("tuios split-window right leaf f.md", LAUNCH),
    ("tuios new-window x --host build -- leaf f.md", LAUNCH),
    ("tuios new-window x --grants admin -- less f", LAUNCH),
    ("tuios new-window x -- vim f.md", LAUNCH),
    ("tuios new-window x -- nvim f.md", LAUNCH),
    ("tuios new-window x -- nvim -R -c q f.md", LAUNCH),
    ("tuios new-window x -- nvim -R +!id f.md", LAUNCH),
    ("tuios new-window x -- nvim -R --cmd q f.md", LAUNCH),
    ("tuios new-window x -- tspin -e make", LAUNCH),
    ("tuios new-window x -- tspin --pager sh f.log", LAUNCH),
    ("tuios new-window x -- lnav -e make", LAUNCH),
    ("tuios new-window x -- lnav host:/var/log", LAUNCH),
    ("tuios new-window x -- hl --config c.toml f.log", LAUNCH),
    ("tuios new-window x -- fx f.json save", LAUNCH),
    ("tuios new-window x -- fx f.json '.a = 1' save", LAUNCH),
    ("tuios new-window x -- otree --debug out.log f.yaml", LAUNCH),
    ("tuios new-window x -- otree --config c.toml f.yaml", LAUNCH),
    ("tuios new-window x -- gonzo --ai-provider claude-code -f app.log", LAUNCH),
    ("tuios new-window x -- gonzo --k8s-enabled", LAUNCH),
    ("tuios new-window x -- gonzo --otlp-enabled", LAUNCH),
    ("tuios new-window x -- gonzo --vmlogs-url http://x", LAUNCH),
    ("tuios run -s s -w build --timeout 600000 -- make test", TYPE),
    ("tuios run -w b -- mytool --help", TYPE),
    ("tuios -w build send-keys ctrl+c", TYPE),
    ("tuios fan 3 'do the thing'", LAUNCH),
    ("tuios start-agent claude -- --model x", LAUNCH),
    ("tuios call send-text", TYPE),
    ("tuios list-windows; tuios send-keys enter", TYPE),
    ("herdr pane $SUB p", UNKNOWN),
    ("tuios respond -w review approve", TYPE),
    ("tuios --server foo send-text x", TYPE),
    ("tuios --server=foo run -- make", TYPE),
    ("tuios --theme x start-agent claude", LAUNCH),
    ("tuios --made-up val send-text x", TYPE),
    ("\\tuios send-text x", TYPE),
    ("tuio''s send-text x", TYPE),
    ('"tuios" send-text x', TYPE),
    ("tuios 'send-text' x", TYPE),
    ("command tuios send-text x", TYPE),
    ("tuios delegate --role review 'look'", LAUNCH),
    ("tuios agent-proto --protocol acp -- claude", LAUNCH),
    ("tuios ship commit -w b -m x", ADMIN),
    ("tuios ship pr -s s --draft", ADMIN),
    ("tuios set-pane-grants -w x --respond", ADMIN),
    ("tuios set-config border_style rounded", ADMIN),
    ("tuios checkpoint restore -w b 2", ADMIN),
    ("tuios record-pane start -w b -o x.cast", READ),
    ("tuios task add -p 'do x' title", TYPE),
    ("tuios task dispatch mode auto", LAUNCH),
    ("tuios plugins run foo act", LAUNCH),
    ("tuios close-window x", DESTROY),
    ("tuios kill-session s", DESTROY),
    ("tuios ask-agent -w a --allow-blocked 'yes'", AGENT),
    ("tuios ask-agent -w a --force 'q'", AGENT),
    ("tuios ask-agent --select 'group:x' --yes 'q'", AGENT),
    ("tuios ask-agent --select 'group:x' --confirm T 'q'", AGENT),
]
PASS = [
    "herdr pane list", "herdr pane current", "herdr pane get p", "herdr pane focus p",
    "herdr workspace list", "herdr tab list", "herdr agent list", "herdr agent wait x --state idle",
    "herdr status", "herdr --version", "herdr",
    "tuios list-windows", "tuios ls", "tuios list-agents -s s", "tuios --skill", "tuios --skill run",
    "tuios --skill all", "tuios --help", "tuios -h send-text", "tuios send-text --help",
    "tuios ask-agent --help", "tuios start-agent -h", "tuios help send-text",
    "tuios note set 'next: run migration'", "tuios ask-human 'run it?' -o yes -o no",
    "tuios send-agent-message -s s -w a 'hi'", "tuios mermaid f.mmd", "tuios task block 3 'stuck'",
    "tuios ask-agent -s s -w a 'is the retry safe?'", "tuios ask-agent --select 'group:x' 'q'",
    "tuios queue -w build 'then migrate'", "tuios queue ls", "tuios review send -w b",
    "tuios ship status -s s", "tuios ship", "tuios checkpoint list -w b", "tuios record-pane stop -w b",
    "tuios plugins list", "tuios task ls", "tuios pane-grants", "tuios wait-for window-idle -w b",
    "rg -n herdr settings.json", "ls ~/.config/herdr/plugins.json",
    "bash ~/.claude/hooks/herdr-agent-state.sh session", "git status",
    "mise exec aqua:mfontanini/presenterm@latest -- presenterm deck.md",
    "tuios split-window right --no-focus --name 'draft x.md' --cwd /tmp/a -- leaf -w '/tmp/a/x y.md'",
    "tuios split-window -s s down --ratio 30 --no-focus -- tail -f app.log",
    "tuios new-window log --no-focus --keep-open -- less -R /tmp/x.log",
    "tuios new-window v -- bat --paging=always -l md f.md",
    "tuios split-window right -- cat -n f",
    "tuios split-window right -- nvim -R f.md", "tuios new-window v -- view f.txt",
    "tuios new-window log -- tspin -f app.log", "tuios new-window log -- lnav -q /tmp/a.log",
    "tuios new-window log -- hl -F -l warn app.log", "tuios new-window c -- csvlens --auto-reload d.csv",
    "tuios new-window m -- moor f.txt", "tuios new-window m -- mdcat -p README.md",
    "tuios new-window j -- fx data.json", "tuios new-window j -- fx --yaml -s a.yaml",
    "tuios new-window o -- otree -R -t yaml k8s.yaml",
    "tuios new-window g -- gonzo -f app.log --follow --web-disabled",
]
MCP_CASES = [
    ("list_agents", {}, False),
    ("send_agent_message", {"text": "hi"}, False),
    ("ask_agent", {"window": "a", "text": "q"}, False),
    ("ask_agent", {"window": "a", "text": "q", "allow_blocked": True}, True),
    ("ask_agent", {"text": "q", "force": True}, True),
    ("ask_agent", {"text": "q", "select": "group:x", "confirm": "T"}, True),
    ("ask_agent", {"text": "q", "select": "group:x"}, False),
    ("send_text", {"window": "a", "text": "ls"}, True),
    ("send_keys", {"keys": "enter"}, True),
    ("respond", {"action": "approve"}, True),
    ("delegate", {"prompt": "x"}, True),
    ("fan", {}, True),
    ("capture_pane", {}, True),
    ("brand_new_tool", {}, True),
]
DENY = [
    "tuios start-agent claude --name w --prompt 'do x'",
    "tuios start-agent claude -- --grants admin",
    "tuios delegate 'add tests'",
    "tuios delegate --role implementation --isolation worktree 'x'",
    "tuios -s repo fan 2 --agent claude 'try it'",
    "cd ~/CX/r && tuios delegate --wait 10m 'x'",
    "tuio''s delegate 'x'",
    "tuios ship push -s s",
    "tuios ship pr -s s --draft --title t",
    "tuios -s s ship pr --yes",
]
NO_DENY = [
    "tuios start-agent claude --grants read,write,task --prompt 'x'",
    "tuios start-agent claude --grants=read -- --model x",
    "tuios delegate --role review 'look'",
    "tuios delegate --role=research 'find it'",
    "tuios delegate --role implementation --grants read,write,task 'x'",
    "tuios fan 2 --agent claude --grants read,write,task 'x'",
    "tuios delegate --help",
    "tuios new-window x -- make",
    "tuios worktree new feat/x --agent claude",
    "tuios send-text -w b ls",
    "tuios ship merge -s s",
    "tuios ship status -s s",
    "tuios ship pr --help",
]
DATA_PASS = [
    "git commit -m 'note: tuios ship push is the user' -m 'and tuios send-text too'",
    'git commit -m "mentions tuios send-text x"',
    "git commit -am 'tuios delegate example'",
    "git commit -q -F - <<'EOF'\nfeat: x\n\n  tuios ship push and tuios delegate 'x'\nEOF",
    "git commit -m \"$(cat <<'EOF'\nuse tuios send-text -w b ls\nEOF\n)\"",
    "cat > notes.md <<'EOF'\ntuios fan 3 'x'\nEOF",
    "git -C ~/r commit -F - <<EOF\ntuios ship pr\nEOF\ngit -C ~/r log -1",
]
DATA_ASK = [
    "bash <<'EOF'\ntuios send-text -w b ls\nEOF",
    "cat <<'EOF' | bash\ntuios send-text -w b ls\nEOF",
    "cat <<'EOF' > x.sh && bash x.sh\ntuios send-text -w b ls\nEOF",
    'git commit -m "$(tuios send-text -w b ls)"',
    "git commit -m `tuios send-text -w b ls`",
    "bash -c \"$(cat <<'EOF'\ntuios send-text -w b ls\nEOF\n)\"",
    "git commit -m 'x'; tuios send-text -w b ls",
    "git commit -F - <<'EOF'\nmsg\nEOF\ntuios send-text -w b ls",
]
MCP_DENY = [
    ("delegate", {"prompt": "x"}, True),
    ("delegate", {"prompt": "x", "role": "implementation"}, True),
    ("delegate", {"prompt": "x", "role": "review"}, False),
    ("delegate", {"prompt": "x", "grants": ["read", "write", "task"]}, False),
    ("fan", {"prompt": "x", "count": 2}, True),
    ("fan", {"prompt": "x", "grants": ["read"]}, False),
    ("send_text", {"text": "x"}, False),
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
        check(command, evaluate(command), None)
    for name, params, want in MCP_CASES:
        check(f"mcp {name} {params}", bool(evaluate_mcp(MCP_PREFIX + name, params)), want)
    for command in DENY:
        check(f"deny {command}", bool(deny_reason(command)), True)
    for command in NO_DENY:
        check(f"no deny {command}", deny_reason(command), None)
    for name, params, want in MCP_DENY:
        check(f"mcp deny {name} {params}", bool(deny_mcp(MCP_PREFIX + name, params)), want)
    for command in DATA_PASS:
        check(f"data pass {command!r}", (evaluate(command), deny_reason(command)), (None, None))
    for command in DATA_ASK:
        check(f"data ask {command!r}", bool(evaluate(command) or deny_reason(command)), True)
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
        check("script --help still scanned", bool(evaluate("viewer.sh --help", d)), True)
    out = evaluate("herdr pane run p ls")
    check("reason text", bool(out) and "types into a pane" in out, True)
    check("help_only loaded", help_only is not None, True)
    print(f"{len(ASK)} ask, {len(PASS)} pass, {len(MCP_CASES)} mcp, "
          f"{len(DENY) + len(NO_DENY) + len(MCP_DENY)} grant, "
          f"{len(DATA_PASS) + len(DATA_ASK)} data, 5 script cases: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
