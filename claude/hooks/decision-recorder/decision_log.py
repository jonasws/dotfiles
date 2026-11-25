#!/usr/bin/env python3
"""Decision log: storage, redaction and normalisation for permission prompts.

The log records the permission prompts the user answered, with the context
the answer was given in, so that a later "did I approve this before, and
where" has an answer. DESIGN.md has the design; this module is its
library, used by decision-recorder.py, agent_decisions.py and, through
record_ask, by the guards that return ask.

  open_db / init_db      connect (hooks never create the schema) / create it
  hmac_of                keyed hash of canonical JSON: the join key of a prompt
  redact_text            what is allowed into input_redacted
  normalise_argv         program, subcommand and flags of one command, as a
                         family, a shape and an args shape
  analyse_bash           a Bash command as segments with workspace context
  build_record           the prompts row and prompt_segments rows of a payload
  store_record           insert them
  record_ask             a guard's "I asked" row; never raises

A write never changes a decision: every function a hook calls either returns
quietly or is wrapped by its caller. The DB path is $AGENT_DECISIONS_DB or
~/.local/share/agent-decisions/decisions.sqlite3, and the HMAC key sits next
to it as hmac.key.

python3 -I decision_log.py --self-test checks the normalisation table of the
design, the redaction cases, the hash, the git push resolver and record_ask.
"""

import hashlib
import hmac
import importlib.util
import json
import math
import os
import re
import sqlite3
import sys
import time
import urllib.parse


def _load(name):
    # cmdshape.py is shared with the other hooks, so it lives one level up.
    here = os.path.dirname(os.path.realpath(__file__))
    path = os.path.join(here, name + ".py")
    if not os.path.exists(path):
        path = os.path.join(os.path.dirname(here), name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cmdshape = _load("cmdshape")
gitctx = _load("gitctx")

SCHEMA_VERSION = 1
BACKTICK = chr(96)
OUTCOMES = ("approved", "approved_always", "declined", "cancelled", "inbox_approved", "inbox_declined", "unresolved")
MAX_SEGMENTS = 20

DDL = """
CREATE TABLE repos (
  id          INTEGER PRIMARY KEY,
  repo_key    TEXT NOT NULL UNIQUE,
  remote_url  TEXT,
  main_path   TEXT,
  default_ref TEXT
);

CREATE TABLE prompts (
  id              INTEGER PRIMARY KEY,
  session_id      TEXT NOT NULL,
  agent_id        TEXT,
  agent_type      TEXT,
  prompt_id       TEXT,
  tool_use_id     TEXT UNIQUE,
  input_hmac      BLOB NOT NULL,
  ts_prompt       INTEGER,
  ts_answer       INTEGER,
  permission_mode TEXT,
  tuios_session   TEXT,
  tuios_pane      TEXT,
  tool_name       TEXT NOT NULL,
  mcp_server      TEXT,
  cwd             TEXT NOT NULL,
  input_redacted  TEXT,
  outcome         TEXT CHECK (outcome IN ('approved', 'approved_always', 'declined', 'cancelled',
                                          'inbox_approved', 'inbox_declined', 'unresolved')),
  outcome_via     TEXT CHECK (outcome_via IN ('transcript', 'post', 'sweep')),
  grant_scope     TEXT,
  reason_code     TEXT,
  circuit_breaker TEXT,
  rule_source     TEXT,
  ran             INTEGER,
  exit_code       INTEGER,
  ctx_partial     INTEGER NOT NULL DEFAULT 0,
  origin          TEXT NOT NULL DEFAULT 'live'
);

CREATE TABLE prompt_segments (
  prompt      INTEGER NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
  seq         INTEGER NOT NULL,
  ts          INTEGER NOT NULL,
  outcome     TEXT,
  family      TEXT NOT NULL,
  shape       TEXT NOT NULL,
  args_shape  TEXT,
  eff_dir     TEXT,
  repo_id     INTEGER REFERENCES repos(id),
  worktree    TEXT,
  branch      TEXT,
  head_sha    TEXT,
  upstream    TEXT,
  upstream_sha TEXT,
  fetched_at  INTEGER,
  branch_class TEXT,
  target      TEXT,
  scope_key   TEXT NOT NULL,
  ctx_uncertain INTEGER NOT NULL DEFAULT 0,
  ctx_input_hmac BLOB NOT NULL,
  PRIMARY KEY (prompt, seq)
) WITHOUT ROWID;

CREATE TABLE asks (
  session_id  TEXT NOT NULL,
  input_hmac  BLOB NOT NULL,
  hook        TEXT NOT NULL,
  ts          INTEGER NOT NULL,
  reason      TEXT,
  detail      TEXT,
  PRIMARY KEY (session_id, input_hmac, hook, ts)
) WITHOUT ROWID;

CREATE TABLE ttl (
  outcome     TEXT PRIMARY KEY,
  recall_days INTEGER NOT NULL,
  text_days   INTEGER NOT NULL,
  keep_days   INTEGER NOT NULL
);

CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID;

CREATE UNIQUE INDEX prompts_tool_use ON prompts(tool_use_id);
CREATE INDEX prompts_pending  ON prompts(session_id, input_hmac, ts_prompt DESC) WHERE outcome IS NULL;
CREATE INDEX prompts_ts       ON prompts(ts_prompt);
CREATE INDEX prompts_prompt   ON prompts(prompt_id);
CREATE INDEX seg_exact        ON prompt_segments(ctx_input_hmac, ts DESC);
CREATE INDEX seg_shape_scope  ON prompt_segments(shape, scope_key, ts DESC);
CREATE INDEX seg_family_scope ON prompt_segments(family, scope_key, ts DESC);
CREATE INDEX seg_family_repo  ON prompt_segments(family, repo_id, ts DESC);
CREATE INDEX seg_repo_branch  ON prompt_segments(repo_id, branch, ts DESC);
CREATE INDEX asks_join        ON asks(session_id, input_hmac, ts DESC);
"""

TTL_DEFAULTS = [
    ("approved", 90, 30, 365), ("approved_always", 90, 30, 365), ("inbox_approved", 90, 30, 365),
    ("declined", 60, 30, 365), ("inbox_declined", 60, 30, 365),
    ("cancelled", 14, 7, 90), ("unresolved", 14, 7, 90),
]


def db_path():
    return os.environ.get("AGENT_DECISIONS_DB") or os.path.expanduser(
        "~/.local/share/agent-decisions/decisions.sqlite3")


def key_path(path=None):
    return os.path.join(os.path.dirname(path or db_path()), "hmac.key")


def now_ms():
    return int(time.time() * 1000)


def open_db(path=None, readonly=False):
    """Return a connection, or None when the DB is missing or not at SCHEMA_VERSION.

    Hooks call this; they never create or migrate the schema."""
    path = path or db_path()
    conn = None
    try:
        if readonly:
            conn = sqlite3.connect("file:" + urllib.parse.quote(path) + "?mode=ro", uri=True, timeout=0.25)
        else:
            if not os.path.exists(path):
                return None
            conn = sqlite3.connect(path, timeout=0.25)
        conn.execute("PRAGMA busy_timeout = 250")
        if not readonly:
            conn.execute("PRAGMA synchronous = NORMAL")
        if conn.execute("PRAGMA user_version").fetchone()[0] != SCHEMA_VERSION:
            conn.close()
            return None
        return conn
    except sqlite3.Error:
        if conn is not None:
            conn.close()
        return None


def init_db(path=None):
    """Create the directory, the DB, its schema and the HMAC key. Safe to repeat."""
    path = path or db_path()
    directory = os.path.dirname(path) or "."
    if not os.path.isdir(directory):
        os.makedirs(directory, mode=0o700, exist_ok=True)
        os.chmod(directory, 0o700)
    if not os.path.exists(path):
        os.close(os.open(path, os.O_CREAT | os.O_WRONLY, 0o600))
    conn = sqlite3.connect(path, timeout=5)
    if conn.execute("PRAGMA user_version").fetchone()[0] == 0:
        conn.execute("PRAGMA auto_vacuum = INCREMENTAL")
        conn.execute("PRAGMA journal_mode = WAL")
        conn.executescript(DDL)
        conn.executemany("INSERT OR IGNORE INTO ttl VALUES (?, ?, ?, ?)", TTL_DEFAULTS)
        conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
        conn.commit()
    os.chmod(path, 0o600)
    kp = key_path(path)
    if not os.path.exists(kp):
        fd = os.open(kp, os.O_CREAT | os.O_WRONLY | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(os.urandom(32))
    return conn


def load_key(path=None):
    try:
        with open(key_path(path), "rb") as f:
            key = f.read()
        return key if len(key) >= 16 else None
    except OSError:
        return None


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def hmac_of(key, obj):
    return hmac.new(key, canonical(obj).encode("utf-8", "surrogatepass"), hashlib.sha256).digest()


# --- redaction (design 6.3) ------------------------------------------------

SECRET_WORDS = r"(?:token|secret|passw(?:or)?d|passwd|key|auth|cookie|session|bearer)"
TOKEN_FORMATS = [
    re.compile(r"-----BEGIN [A-Z ]*-----.*?(?:-----END [A-Z ]*-----|$)", re.DOTALL),
    re.compile(r"\bxox[a-z]-[A-Za-z0-9-]+"),
    re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{5,}\.eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*"),
]
HEADER_RE = re.compile(r"\b(Authorization|Proxy-Authorization|Cookie|X-Api-Key)(\s*[:=]\s*)[^'\"\n]+", re.I)
URL_USERINFO = re.compile(r"(\b[A-Za-z][A-Za-z0-9+.-]*://)[^/\s:@'\"]+(?::[^/\s@'\"]*)?@")
URL_QUERY = re.compile(r"([?&][\w.-]*(?:" + SECRET_WORDS[3:-1] + r"|sig|signature)[\w.-]*=)[^&\s'\"]+", re.I)
FLAG_VALUE = re.compile(r"(--?[A-Za-z0-9_.-]*" + SECRET_WORDS + r"[A-Za-z0-9_.-]*)(=|[ \t]+)(\"[^\"]*\"|'[^']*'|[^\s;|&]+)",
                        re.I)
ENV_VALUE = re.compile(r"(?<![\w-])([A-Za-z0-9_]*" + SECRET_WORDS + r"[A-Za-z0-9_]*=)(\"[^\"]*\"|'[^']*'|[^\s;|&]+)",
                       re.I)
LONG_RUN = re.compile(r"[A-Za-z0-9+_=-]{32,}")
MARK = "<redacted>"
MAX_TEXT = 2000


def entropy(s):
    if not s:
        return 0.0
    counts = {c: s.count(c) for c in set(s)}
    return -sum(n / len(s) * math.log2(n / len(s)) for n in counts.values())


def secret_shaped(s):
    if any(p.search(s) for p in TOKEN_FORMATS):
        return True
    return len(s) >= 20 and entropy(s) >= 4.0 and re.search(r"\d", s) is not None and re.search(r"[A-Za-z]", s) is not None


def _run_repl(m):
    run = m.group(0)
    return MARK if secret_shaped(run) or (re.search(r"\d", run) and re.search(r"[A-Za-z]", run) and entropy(run) >= 3.6) else run


def redact_text(text):
    """Return text with secrets, heredoc bodies and anything past 2,000 characters removed."""
    text = cmdshape.strip_heredocs(text, "<heredoc>")
    for pattern in TOKEN_FORMATS:
        text = pattern.sub(MARK, text)
    text = HEADER_RE.sub(lambda m: m.group(1) + m.group(2) + MARK, text)
    text = URL_USERINFO.sub(lambda m: m.group(1) + MARK + "@", text)
    text = URL_QUERY.sub(lambda m: m.group(1) + MARK, text)
    text = FLAG_VALUE.sub(lambda m: m.group(1) + m.group(2) + MARK, text)
    text = ENV_VALUE.sub(lambda m: m.group(1) + MARK, text)
    text = LONG_RUN.sub(_run_repl, text)
    return text if len(text) <= MAX_TEXT else text[:MAX_TEXT] + "..."


def _redact_obj(obj, depth=0):
    if depth > 6:
        return MARK
    if isinstance(obj, dict):
        return {k: (MARK if re.search(SECRET_WORDS, str(k), re.I) else _redact_obj(v, depth + 1)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_redact_obj(v, depth + 1) for v in obj[:50]]
    if isinstance(obj, str):
        return redact_text(obj)
    return obj


FILE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


def redact_input(tool_name, tool_input):
    """The text kept in input_redacted. File tools keep the path, never the content."""
    tool_input = tool_input if isinstance(tool_input, dict) else {}
    if tool_name == "Bash":
        return redact_text(str(tool_input.get("command") or ""))
    if tool_name in FILE_TOOLS:
        return json.dumps({"file_path": tool_input.get("file_path") or tool_input.get("notebook_path")})
    out = canonical(_redact_obj(tool_input))
    return out if len(out) <= MAX_TEXT else out[:MAX_TEXT] + "..."


# --- normalisation (design 6.2) ---------------------------------------------

WORD = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
TASK_WORD = re.compile(r"^[A-Za-z][A-Za-z0-9_:.-]*$")
BENIGN = re.compile(r"^[A-Za-z0-9._:@/#-]+$")
SECRET_FLAG = re.compile(SECRET_WORDS, re.I)
DEPTH0 = {"rg", "fd", "jq", "curl", "ssh", "sd", "python3", "python", "node", "ls", "cat", "grep", "sed", "awk"}
DEPTH2 = {"aws", "gh", "slackcli", "twg", "cdk"}
RUN_PROGS = {"npm", "pnpm", "yarn", "mise", "uv"}
TRIVIAL = {"cd", "pwd", "echo", "true", "date", "export", "unset"}
# A script run by one of these is the command that matters: python3 foo.py, not python3.
INTERPRETERS = {"python", "python3", "node", "bash", "sh", "zsh", "ruby", "perl", "deno", "bun"}
SINKS = {"jq", "head", "tail", "wc", "sort"}
FREE_TEXT = {
    "tuios send-text", "tuios send-keys", "tuios ask-agent", "tuios send-agent-message", "tuios respond",
    "tuios ask-human", "tuios note", "herdr pane",
}
# Value flags per program: True keeps a benign value in args_shape, False masks it.
GENERIC_VALUE_FLAGS = {
    "--summary": False, "--message": False, "-m": False, "--title": False, "--body": False,
    "--description": False, "--comment": False, "--text": False, "--query": False,
}
VALUE_FLAGS = {
    "tuios": {"-s": True, "-w": True, "-p": True, "--select": True, "--window": True, "--workspace": True,
              "--pane": True},
    "herdr": {"-s": True, "-w": True, "-p": True, "--select": True, "--window": True, "--workspace": True,
              "--pane": True},
    "git": {"-C": True, "-c": False},
    "aws": {"--profile": True, "--region": True, "--output": True, "--endpoint-url": False},
    "kubectl": {"-n": True, "--namespace": True, "--context": True},
    "helm": {"-n": True, "--namespace": True, "--kube-context": True},
    "twg": {"-o": True, "--output": True},
    "gh": {"-R": True, "--repo": True},
}


def _prog(token):
    return "<expansion>" if "$" in token or BACKTICK in token else os.path.basename(token)


def _is_flag(tok):
    return len(tok) > 1 and tok.startswith("-") and not re.fullmatch(r"-\d*\.\d+", tok)


def _flag_items(tok, args, i, table):
    """Return ([(name, value, keep, eq)], next index) for one flag token."""
    if tok.startswith("--"):
        name, eq, value = tok.partition("=")
        if eq:
            return [(name, value, table.get(name, False), True)], i
        if name in table and i < len(args):
            return [(name, args[i], table[name], False)], i + 1
        return [(name, None, False, False)], i
    if re.fullmatch(r"-\d+", tok):
        return [("-<n>", None, False, False)], i
    body = tok[1:]
    if len(body) == 1:
        if tok in table and i < len(args):
            return [(tok, args[i], table[tok], False)], i + 1
        return [(tok, None, False, False)], i
    if body.isalpha():
        return [("-" + c, None, False, False) for c in sorted(body)], i
    return [("-" + body[0], None, False, False)], i


def mask_positional(tok):
    """The shape of a positional: <path>, <url:host>, <s3:bucket>, <n>, <arg>, <expansion>."""
    if "$" in tok or BACKTICK in tok or tok == "<expansion>":
        return "<expansion>"
    m = re.match(r"^s3://([^/]+)", tok)
    if m:
        return f"<s3:{m.group(1)}>"
    m = re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://(?:[^/@]*@)?([^/:?#]+)", tok)
    if m:
        return f"<url:{m.group(1)}>"
    if re.fullmatch(r"\d+", tok):
        return "<n>"
    if "/" in tok or tok.startswith(("~", ".")):
        return "<path>"
    return "<arg>"


def benign(tok):
    return len(tok) <= 40 and bool(BENIGN.match(tok)) and not secret_shaped(tok)


def keep_positional(tok):
    """The args_shape form of a positional: itself when benign, else its shape."""
    masked = mask_positional(tok)
    if masked.startswith(("<s3:", "<url:", "<expansion")):
        return masked
    return tok if benign(tok) else "<arg>"


def normalise_argv(argv, env=()):
    """Return {"family", "shape", "args_shape", "via_env"} for one command's argv."""
    prog = _prog(argv[0])
    table = dict(GENERIC_VALUE_FLAGS)
    table.update(VALUE_FLAGS.get(prog, {}))
    need = 0 if prog in DEPTH0 else (2 if prog in DEPTH2 else 1)
    pre, subs, flags, pos, sflags = [], [], [], [], []
    order = []  # tokens as written, so args_shape keeps the command's own order
    closed = need == 0
    args, i = argv[1:], 0
    while i < len(args):
        tok = args[i]
        i += 1
        if tok == "--":
            pos.extend(args[i:])
            order.extend(("p", t) for t in args[i:])
            break
        if _is_flag(tok):
            items, i = _flag_items(tok, args, i, table)
            if prog in INTERPRETERS and pos:
                sflags.extend(items)
            else:
                (pre if not closed and len(subs) < need else flags).extend(items)
            order.append(("f", items))
        elif not closed and len(subs) < need and (WORD.match(tok) or (subs and prog in RUN_PROGS and TASK_WORD.match(tok))):
            subs.append(tok)
            order.append(("s", tok))
            if len(subs) == 1 and ((prog in RUN_PROGS and tok == "run") or (prog == "docker" and tok == "compose")):
                need = 2
        else:
            closed = True
            pos.append(tok)
            order.append(("p", tok))
    script = None
    if prog in INTERPRETERS and pos and not _is_flag(pos[0]) and "$" not in pos[0]:
        script = os.path.basename(pos[0])
        pos = pos[1:]
    family = " ".join([prog] + subs + ([script] if script else []))

    def flag_shape(items):
        return [n + (" <arg>" if v is not None and not eq else "") for n, v, _, eq in items]

    def flag_args(items):
        out = []
        for n, v, keep, eq in items:
            shown = None
            if v is not None:
                keep = keep and not SECRET_FLAG.search(n)
                shown = keep_positional(v) if keep else "<arg>"
            out.append(n if v is None else (f"{n}={shown}" if eq else f"{n} {shown}"))
        return out

    lead = [script] if script else []
    shape = [prog] + flag_shape(pre) + subs + flag_shape(flags) + lead + flag_shape(sflags) + [mask_positional(p) for p in pos]
    free = family in FREE_TEXT
    args_shape, script_seen = [prog], False
    for kind, item in order:
        if kind == "f":
            args_shape.extend(flag_args(item))
        elif kind == "s":
            args_shape.append(item)
        elif script and not script_seen:
            script_seen = True
            args_shape.append(script)
        else:
            args_shape.append("<arg>" if free else keep_positional(item))
    return {"family": family, "shape": " ".join(shape), "args_shape": " ".join(args_shape),
            "via_env": [e.split("=", 1)[0] + "=<v>" for e in env]}


def analyse_bash(command, cwd):
    """Return (segments, uncertain): the non-trivial commands of a Bash text.

    Each segment holds family, shape, args_shape, argv, via, dir, uncertain and
    branch (an override from an earlier checkout). cd, pwd, echo, true and date
    are left out, as are jq, head, tail, wc and sort after a pipe, unless that
    would leave nothing."""
    parsed = cmdshape.command_segments(command)
    segs = parsed["segments"]
    if parsed["error"] or not segs:
        words = command.split()
        first = _prog(words[0]) if words else "bash"
        return [{"family": first, "shape": first + " <unparsed>", "args_shape": first + " <unparsed>", "argv": words[:1],
                 "via": [], "dir": cwd, "uncertain": True, "branch": None}], True
    tracks = gitctx.track_dirs(segs, cwd, parsed["odd"])
    out = []
    for seg, track in zip(segs, tracks):
        norm = normalise_argv(seg["argv"], seg["env"])
        norm.update({"argv": seg["argv"], "via": seg["via"] + norm.pop("via_env"), "dir": track["dir"],
                     "uncertain": track["uncertain"], "branch": track["branch"],
                     "drop": os.path.basename(seg["argv"][0]) in TRIVIAL or (seg["piped"] and seg["argv"][0] in SINKS),
                     "env": seg["env"]})
        out.append(norm)
    kept = [s for s in out if not s["drop"]] or out[:1]
    return kept[:MAX_SEGMENTS], parsed["odd"]


def normalise_tool(tool_name, tool_input):
    """Return family, shape, args_shape for a tool that isn't Bash."""
    tool_input = tool_input if isinstance(tool_input, dict) else {}
    if tool_name in FILE_TOOLS:
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        return tool_name, f"{tool_name} {path}", f"{tool_name} {path}"
    if tool_name == "WebFetch":
        host = urllib.parse.urlsplit(str(tool_input.get("url") or "")).hostname or "<unknown>"
        return tool_name, f"WebFetch {host}", f"WebFetch {host}"
    if tool_name.startswith("mcp__"):
        shape = " ".join([tool_name] + sorted(tool_input))
        shown = [f"{k}={v if isinstance(v, str) and benign(v) else '<arg>'}"
                 for k in MCP_ARG_KEYS.get(tool_name, MCP_ARG_DEFAULT) if k in tool_input
                 for v in [tool_input[k]]]
        return tool_name, shape, " ".join([shape] + shown)
    return tool_name, tool_name, tool_name


MCP_ARG_DEFAULT = ("action", "method", "operation", "session")
MCP_ARG_KEYS = {}


# --- targets (design 5.3) ----------------------------------------------------

PUSH_VALUE_FLAGS = {"-o", "--push-option", "--repo", "--receive-pack", "--exec", "--signed"}
BRANCH_FAMILIES = {"git reset", "git clean", "git rebase", "git branch"}
PROTECTED_CLASSES = ("default", "protected")


def resolve_git_push(seg, info, repo):
    argv = seg["argv"]
    _, rest, _ = gitctx._git_subcommand(argv)
    force = delete = tags = every = False
    pos, i = [], 0
    while i < len(rest):
        a = rest[i]
        i += 1
        if a == "--":
            pos += rest[i:]
            break
        if a.startswith("--"):
            name = a.split("=", 1)[0]
            force = force or name in ("--force", "--force-with-lease", "--force-if-includes")
            delete = delete or name == "--delete"
            tags = tags or name == "--tags"
            every = every or name in ("--all", "--mirror")
            if name in PUSH_VALUE_FLAGS and "=" not in a:
                i += 1
        elif a.startswith("-") and len(a) > 1:
            force = force or "f" in a[1:]
            delete = delete or "d" in a[1:]
            if a in PUSH_VALUE_FLAGS:
                i += 1
        else:
            pos.append(a)
    branch = info.get("branch") if info else None
    default = info.get("default_branch") if info else None
    remote = pos[0] if pos else None
    if remote is None and branch and repo is not None:
        remote = repo.config_value("branch", branch, "remote")
    remote = remote or "origin"
    refspecs = pos[1:]
    dsts = []
    if every:
        dsts = [("*", True)]
    elif refspecs:
        for spec in refspecs:
            plus = spec.startswith("+")
            force = force or plus
            spec = spec.lstrip("+")
            src, colon, dst = spec.partition(":")
            if not colon:
                dst = branch if src == "HEAD" else src
            elif not src:
                delete = True
            dsts.append((dst or None, False))
    elif branch:
        mode = (info.get("push_default") or "simple") if info else "simple"
        upstream = info.get("upstream") or ""
        dst = upstream.split("/", 1)[1] if mode in ("upstream", "tracking") and "/" in upstream else branch
        dsts = [(dst, False)]
    else:
        dsts = [(None, False)]
    classes, shown = [], []
    for dst, wild in dsts:
        if wild:
            classes.append("protected")
            shown.append("*")
        elif dst is None:
            classes.append("unknown")
            shown.append(None)
        elif dst.startswith("refs/tags/"):
            classes.append("protected")
            shown.append(dst)
        else:
            name = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
            classes.append(gitctx.branch_class(name, default))
            shown.append(name)
    dst_class = next((c for c in PROTECTED_CLASSES if c in classes), None) or \
        ("unknown" if "unknown" in classes else (classes[0] if classes else "unknown"))
    first = shown[0] if shown else None
    before = repo.ref_sha(f"refs/remotes/{remote}/{first}") if repo is not None and first and first != "*" else None
    target = {"remote": remote, "dst": first, "dst_class": dst_class, "force": force, "delete": delete,
              "tags": tags, "dst_sha_before": before}
    if len(shown) > 1:
        target["dsts"] = shown
    scope = f"dst={dst_class}|force={int(force)}|delete={int(delete)}"
    return target, scope


def resolve_branch_family(seg, info, repo):
    cls = info.get("branch_class") if info else None
    return {"branch": info.get("branch") if info else None, "branch_class": cls}, f"bc={cls}"


# Resolvers not written yet fall back to the generic repo scope: aws and cdk
# (profile, account, region), kubectl and helm (context, namespace), slackcli
# (workspace, channels), tuios and herdr (target session), run_script (boto3 operations).
RESOLVERS = {"git push": resolve_git_push}
for _family in BRANCH_FAMILIES:
    RESOLVERS[_family] = resolve_branch_family


def is_protected_push(target, branch_class):
    """True when a push segment's destination is main, master, the default branch or a protected one."""
    cls = (target or {}).get("dst_class")
    return cls in PROTECTED_CLASSES or (cls == "unknown" and branch_class in PROTECTED_CLASSES)


# --- records -----------------------------------------------------------------

def _info_for(path, cache, override_branch=None):
    key = (path, override_branch)
    if key in cache:
        return cache[key]
    repo = gitctx.find_repo(path) if path else None
    info = repo.info() if repo else None
    if info and override_branch:
        info = dict(info, branch=override_branch, head_sha=None, upstream=None, upstream_sha=None,
                    branch_class=gitctx.branch_class(override_branch, info["default_branch"]))
    cache[key] = (repo, info)
    return cache[key]


def _segment_row(seq, norm, seg_input, repo, info, key, ts, target, scope_tail, uncertain):
    repo_key = info["repo_key"] if info else "none"
    scope = f"repo={repo_key}" + (f"|{scope_tail}" if scope_tail else "")
    row = {
        "seq": seq, "ts": ts, "family": norm["family"], "shape": norm["shape"], "args_shape": norm["args_shape"],
        "eff_dir": norm.get("dir"), "repo": info, "worktree": info.get("worktree") if info else None,
        "branch": info.get("branch") if info else None, "head_sha": info.get("head_sha") if info else None,
        "upstream": info.get("upstream") if info else None, "upstream_sha": info.get("upstream_sha") if info else None,
        "fetched_at": info.get("fetched_at") if info else None, "branch_class": info.get("branch_class") if info else None,
        "target": json.dumps(dict(target or {}, via=norm["via"]) if norm.get("via") else target, sort_keys=True)
        if (target or norm.get("via")) else None,
        "scope_key": scope, "ctx_uncertain": int(bool(uncertain)),
        "ctx_input_hmac": hmac_of(key, {"input": seg_input, "scope": scope}),
    }
    return row


def build_record(payload, key, partial=None, ts=None):
    """Return (prompt dict, [segment dicts]) for a PermissionRequest-shaped payload.

    With partial (a dict holding the transcript's gitBranch) the row is marked
    ctx_partial: repo and worktree come from the folder as it is now and the
    branch from the transcript, while commit, upstream and target, which only
    the moment of the prompt knew, stay empty."""
    tool = payload.get("tool_name") or ""
    tin = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    cwd = payload.get("cwd") or ""
    ts = ts or now_ms()
    prompt = {
        "session_id": payload.get("session_id") or "", "agent_id": payload.get("agent_id"),
        "agent_type": payload.get("agent_type"), "prompt_id": payload.get("prompt_id"),
        "input_hmac": hmac_of(key, tin), "ts_prompt": None if partial else ts,
        "permission_mode": payload.get("permission_mode"),
        "tuios_session": os.environ.get("TUIOS_SESSION") if not partial else None,
        "tuios_pane": os.environ.get("TUIOS_PANE_ID") if not partial else None,
        "tool_name": tool, "mcp_server": tool.split("__")[1] if tool.startswith("mcp__") and tool.count("__") >= 2 else None,
        "cwd": cwd, "input_redacted": redact_input(tool, tin), "ctx_partial": int(bool(partial)),
    }
    cache, segments = {}, []
    if tool == "Bash":
        norms, odd = analyse_bash(str(tin.get("command") or ""), cwd)
        for seq, norm in enumerate(norms):
            seg_input = " ".join(norm["argv"])
            if partial:
                same = norm["dir"] == cwd
                repo, info = _info_for(norm["dir"], cache, partial.get("branch") if same else None)
                if info and not same:
                    info = dict(info, branch=None, head_sha=None, upstream=None, upstream_sha=None, branch_class=None)
                row = _segment_row(seq, norm, seg_input, repo, info, key, ts, None, None, True)
                row["scope_key"] = "partial"
                row["ctx_input_hmac"] = hmac_of(key, {"input": seg_input, "scope": "partial"})
            else:
                repo, info = _info_for(norm["dir"], cache, norm["branch"])
                resolver = RESOLVERS.get(norm["family"])
                target, tail = resolver(norm, info, repo) if resolver else ({}, None)
                row = _segment_row(seq, norm, seg_input, repo, info, key, ts, target, tail, norm["uncertain"])
            segments.append(row)
    else:
        family, shape, args_shape = normalise_tool(tool, tin)
        path = tin.get("file_path") or tin.get("notebook_path")
        where = os.path.dirname(path) if tool in FILE_TOOLS and path else cwd
        norm = {"family": family, "shape": shape, "args_shape": args_shape, "dir": where, "via": []}
        if partial:
            repo, info = _info_for(where, cache, partial.get("branch"))
            if tool in FILE_TOOLS and path and info and info.get("toplevel") and path.startswith(info["toplevel"]):
                norm["shape"] = norm["args_shape"] = f"{tool} {os.path.relpath(path, info['toplevel'])}"
            row = _segment_row(0, norm, canonical(tin), repo, info, key, ts, None, None, True)
            row["scope_key"] = "partial"
            row["ctx_input_hmac"] = hmac_of(key, {"input": tin, "scope": "partial"})
        else:
            repo, info = _info_for(where, cache)
            target, tail = {}, None
            if tool in FILE_TOOLS and path:
                top = info["toplevel"] if info else cwd
                rel = os.path.relpath(path, top) if path.startswith(top or "/") else path
                norm["shape"] = norm["args_shape"] = f"{tool} {rel}"
                target = {"path": rel}
                tail = f"bc={info['branch_class'] if info else None}|top={rel.split(os.sep)[0] if not rel.startswith(os.sep) else '/'}"
            elif tool == "WebFetch":
                host = shape.split(" ", 1)[1]
                target, tail = {"host": host}, None
            row = _segment_row(0, norm, canonical(tin), repo, info, key, ts, target, tail, False)
            if tool == "WebFetch":
                row["scope_key"] = f"host={target['host']}"
                row["ctx_input_hmac"] = hmac_of(key, {"input": tin, "scope": row["scope_key"]})
        segments.append(row)
    return prompt, segments


PROMPT_COLUMNS = ("session_id", "agent_id", "agent_type", "prompt_id", "input_hmac", "ts_prompt", "permission_mode",
                  "tuios_session", "tuios_pane", "tool_name", "mcp_server", "cwd", "input_redacted", "ctx_partial")


def store_record(conn, prompt, segments, extra=None):
    """Insert a prompts row and its segments; returns the prompt id. Caller commits.

    extra sets further prompts columns (outcome and the like) for a row the
    reconciler builds from the transcript."""
    values = dict(prompt, **(extra or {}))
    cols = list(PROMPT_COLUMNS) + [c for c in (extra or {}) if c not in PROMPT_COLUMNS]
    cur = conn.execute(f"INSERT INTO prompts ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})",
                       [values.get(c) for c in cols])
    pid = cur.lastrowid
    for seg in segments:
        repo_id = None
        info = seg["repo"]
        if info:
            conn.execute(
                "INSERT INTO repos (repo_key, remote_url, main_path, default_ref) VALUES (?, ?, ?, ?) "
                "ON CONFLICT(repo_key) DO UPDATE SET remote_url = excluded.remote_url, main_path = excluded.main_path, "
                "default_ref = coalesce(excluded.default_ref, default_ref)",
                (info["repo_key"], info["remote_url"], info["main_path"], info["default_branch"]))
            repo_id = conn.execute("SELECT id FROM repos WHERE repo_key = ?", (info["repo_key"],)).fetchone()[0]
        conn.execute(
            "INSERT INTO prompt_segments (prompt, seq, ts, outcome, family, shape, args_shape, eff_dir, repo_id, worktree, "
            "branch, head_sha, upstream, upstream_sha, fetched_at, branch_class, target, scope_key, ctx_uncertain, "
            "ctx_input_hmac) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (pid, seg["seq"], prompt["ts_prompt"] or seg["ts"], values.get("outcome"), seg["family"], seg["shape"],
             seg["args_shape"], seg["eff_dir"], repo_id, seg["worktree"], seg["branch"], seg["head_sha"], seg["upstream"],
             seg["upstream_sha"], seg["fetched_at"], seg["branch_class"], seg["target"], seg["scope_key"],
             seg["ctx_uncertain"], seg["ctx_input_hmac"]))
    return pid


def record_ask(hook, payload, reason=None, detail=None):
    """Write the guard's ask row. Call it after the decision is printed; it never raises."""
    conn = None
    try:
        conn = open_db()
        key = load_key() if conn else None
        if not key:
            return
        tin = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
        conn.execute(
            "INSERT OR IGNORE INTO asks (session_id, input_hmac, hook, ts, reason, detail) VALUES (?, ?, ?, ?, ?, ?)",
            (payload.get("session_id") or "", hmac_of(key, tin), str(hook), now_ms(),
             redact_text(str(reason))[:500] if reason else None,
             redact_text(canonical(detail)) if detail is not None else None))
        conn.commit()
    except Exception:
        pass
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass


# --- self-test ------------------------------------------------------------------

TABLE = [
    ("git push --force origin feat/x", "git push", "git push --force <arg> <path>", "git push --force origin feat/x"),
    ("cd ~/CX/foo && git push -f", "git push", "git push -f", "git push -f"),
    ("fnox exec -- aws s3 cp s3://bkt/k ./f", "aws s3 cp", "aws s3 cp <s3:bkt> <path>", "aws s3 cp <s3:bkt> ./f"),
    ("tuios -s dotfiles send-text -w ab12 'ls'", "tuios send-text", "tuios -s <arg> send-text -w <arg> <arg>",
     "tuios -s dotfiles send-text -w ab12 <arg>"),
    ("twg jira workitem edit CX-812 --summary 'x'", "twg jira workitem", "twg jira workitem --summary <arg> <arg> <arg>",
     "twg jira workitem edit CX-812 --summary <arg>"),
]
EXTRA_SHAPES = [
    ("rg -n foo src/", "rg", "rg -n <arg> <path>"),
    ("curl -sL https://example.com/x?a=1", "curl", "curl -L -s <url:example.com>"),
    ("git log -1 --format=%h", "git log", "git log -<n> --format"),
    ("rm -rf $HOME/x", "rm", "rm -f -r <expansion>"),
    ("npm run build -- --watch", "npm run build", "npm run build <arg>"),
    ("mise run test:unit", "mise run test:unit", "mise run test:unit"),
    ("docker compose up -d", "docker compose up", "docker compose up -d"),
    ("git commit -m 'fix: thing'", "git commit", "git commit -m <arg>"),
    ("make -j8 all", "make all", "make -j all"),
    ("export A=1 && export B=2 && python3 -I ~/x/decision-recorder.py --self-test", "python3 decision-recorder.py",
     "python3 -I decision-recorder.py --self-test"),
    ("python3 -I tool.py ./data.json", "python3 tool.py", "python3 -I tool.py <path>"),
    ("bash ./scripts/run.sh deploy", "bash run.sh", "bash run.sh <arg>"),
    ("node --version", "node", "node --version"),
]
# args_shape keeps the order the command was written in, even where the parser
# can't tell a flag's value from a positional.
ARGS_ORDER = [
    ("atuin search --cwd . --limit 3 deploy", "atuin search --cwd . --limit 3 deploy"),
    ("python3 -I tool.py --self-test", "python3 -I tool.py --self-test"),
    ("git log -1 --format=%h origin/HEAD", "git log -<n> --format=<arg> origin/HEAD"),
]
SECRETS = {
    "curl -H 'Authorization: Bearer abc123def' https://x.test/a": "abc123def",
    "curl -H 'X-Api-Key: k-12345' https://x.test/a": "k-12345",
    "curl -b 'Cookie: sid=zzz999' https://x.test": "zzz999",
    "export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG ; ls": "wJalrXUtnFEMI",
    "GH_TOKEN=hunter2 gh pr list": "hunter2",
    "slackcli --token xoxb-1234-5678-abcdefgh conversations list": "xoxb-1234",
    "tool --api-key=s3cr3tvalue run": "s3cr3tvalue",
    "tool --password 'two words' run": "two words",
    "git clone https://user:pw0rd@github.com/x/y.git": "pw0rd",
    "curl 'https://x.test/y?access_token=tok123&q=1'": "tok123",
    "echo ghp_abcdefghijklmnopqrstuvwxyz0123456789": "ghp_abcdef",
    "echo github_pat_11ABCDEFG0123456789_abcdefghijklmnop": "github_pat_11",
    "aws configure set x AKIAABCDEFGHIJKLMNOP": "AKIAABCDEF",
    "echo sk-abcdefghijklmnopqrstuvwx": "sk-abcdefgh",
    "echo eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c": "eyJhbGci",
    "echo -----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg\n-----END PRIVATE KEY-----": "MIIEvQ",
    "echo 4f9a2c8e1b7d3056a9c4e8f2b1d7a3c5e9f0": "4f9a2c8e1b7d",
    "cat > f <<'EOF'\nsecret body line\nEOF\nls": "secret body line",
}
KEEP = ["git push --force origin feat/x", "ls -la ~/dotfiles/claude/hooks", "rg 'ask rule' --glob '*.json'",
        "git log --oneline origin/main..HEAD", "mise run decisions:doctor"]


def _git_repo(tmp):
    import subprocess
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update({"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull, "GIT_AUTHOR_NAME": "t",
                "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"})

    def git(*args):
        return subprocess.run(["git", "-c", "commit.gpgsign=false", *args], cwd=tmp, env=env, check=True,
                              capture_output=True, text=True).stdout.strip()

    git("init", "-q", "-b", "main")
    with open(os.path.join(tmp, "f"), "w") as f:
        f.write("x")
    git("add", "f")
    git("commit", "-q", "-m", "one")
    sha = git("rev-parse", "HEAD")
    git("remote", "add", "origin", "https://github.com/acme/repo.git")
    git("update-ref", "refs/remotes/origin/main", sha)
    git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
    git("config", "branch.main.remote", "origin")
    git("config", "branch.main.merge", "refs/heads/main")
    git("branch", "feat/x")
    git("update-ref", "refs/remotes/origin/feat/x", sha)
    return git, sha


def self_test():
    import shutil
    import tempfile

    failures = 0

    def check(label, got, want):
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")

    for command, family, shape, args_shape in TABLE:
        segs, _ = analyse_bash(command, "/w")
        check(command + " [one segment]", len(segs), 1)
        check(command + " [family]", segs[0]["family"], family)
        check(command + " [shape]", segs[0]["shape"], shape)
        check(command + " [args]", segs[0]["args_shape"], args_shape)
    for command, family, shape in EXTRA_SHAPES:
        segs, _ = analyse_bash(command, "/w")
        check(command, (segs[0]["family"], segs[0]["shape"]), (family, shape))
    for command, args_shape in ARGS_ORDER:
        segs, _ = analyse_bash(command, "/w")
        check(command + " [args order]", segs[0]["args_shape"], args_shape)
    check("trivial dropped", [s["family"] for s in analyse_bash("cd x && echo hi && rg a | head -3 | sort", "/w")[0]], ["rg"])
    check("only trivial kept", [s["family"] for s in analyse_bash("cd ~/x", "/w")[0]], ["cd"])
    check("two real segments", [s["family"] for s in analyse_bash("git pull && git push", "/w")[0]], ["git pull", "git push"])
    check("via", analyse_bash("fnox exec -- aws s3 ls", "/w")[0][0]["via"], ["fnox exec"])
    check("env value masked", analyse_bash("TOKEN=abc make x", "/w")[0][0]["via"], ["TOKEN=<v>"])
    check("unparsed", analyse_bash("echo 'x", "/w")[0][0]["shape"], "echo <unparsed>")
    check("mcp shape", normalise_tool("mcp__tuios__capture_pane", {"session": "dotfiles", "window": "ab", "lines": 5}),
          ("mcp__tuios__capture_pane", "mcp__tuios__capture_pane lines session window",
           "mcp__tuios__capture_pane lines session window session=dotfiles"))
    check("edit", normalise_tool("Edit", {"file_path": "/a/b.py", "old_string": "x"}), ("Edit", "Edit /a/b.py", "Edit /a/b.py"))
    check("webfetch", normalise_tool("WebFetch", {"url": "https://docs.example.com/a?b=1"})[1], "WebFetch docs.example.com")

    for command, secret in SECRETS.items():
        out = redact_text(command)
        check("redact " + command[:30], secret in out, False)
    for command in KEEP:
        check("keep " + command, redact_text(command), command)
    check("redacted marker", "<redacted>" in redact_text("tool --token abc"), True)
    check("truncated", len(redact_text("echo " + "a b " * 1000)) <= MAX_TEXT + 3, True)
    check("input redacted, edit", redact_input("Edit", {"file_path": "/x", "new_string": "secret"}), '{"file_path": "/x"}')
    check("input redacted, mcp", "hunter2" in redact_input("mcp__x__y", {"password": "hunter2", "a": "b"}), False)

    key = b"k" * 32
    check("canonical", canonical({"b": "é", "a": 1}), '{"a":1,"b":"é"}')
    check("hmac stable", hmac_of(key, {"a": 1, "b": [1, 2]}), hmac_of(key, {"b": [1, 2], "a": 1}))
    check("hmac differs", hmac_of(key, {"a": 1}) == hmac_of(key, {"a": 2}), False)
    check("hmac keyed", hmac_of(key, {"a": 1}) == hmac_of(b"j" * 32, {"a": 1}), False)
    check("hmac length", len(hmac_of(key, {})), 32)

    tmp = os.path.realpath(tempfile.mkdtemp(prefix="decision-log-"))
    saved = os.environ.get("AGENT_DECISIONS_DB")
    try:
        os.environ["AGENT_DECISIONS_DB"] = os.path.join(tmp, "none", "d.sqlite3")
        check("missing DB opens as None", open_db(), None)
        record_ask("pane-control-guard", {"session_id": "s", "tool_input": {"command": "x"}}, "why", {"a": 1})
        record_ask("g", None)
        record_ask("g", {"tool_input": "not a dict"})
        check("record_ask didn't create the DB", os.path.exists(os.path.join(tmp, "none")), False)

        os.environ["AGENT_DECISIONS_DB"] = os.path.join(tmp, "empty.sqlite3")
        sqlite3.connect(os.environ["AGENT_DECISIONS_DB"]).close()
        check("DB without schema opens as None", open_db(), None)
        record_ask("g", {"session_id": "s", "tool_input": {}}, "x")

        path = os.path.join(tmp, "data", "d.sqlite3")
        os.environ["AGENT_DECISIONS_DB"] = path
        init_db(path).close()
        init_db(path).close()
        check("dir mode", oct(os.stat(os.path.dirname(path)).st_mode & 0o777), "0o700")
        check("db mode", oct(os.stat(path).st_mode & 0o777), "0o600")
        check("key", (oct(os.stat(key_path(path)).st_mode & 0o777), len(load_key(path))), ("0o600", 32))
        conn = open_db()
        check("opens", conn is not None, True)
        check("wal", conn.execute("PRAGMA journal_mode").fetchone()[0], "wal")
        check("auto_vacuum", conn.execute("PRAGMA auto_vacuum").fetchone()[0], 2)
        check("ttl rows", conn.execute("SELECT count(*) FROM ttl").fetchone()[0], 7)
        record_ask("pane-control-guard", {"session_id": "s1", "tool_input": {"command": "tuios send-text x"}},
                   "types into a shell with token=abc123", {"ops": ["ListBuckets"]})
        row = conn.execute("SELECT session_id, hook, reason, detail FROM asks").fetchone()
        check("ask row", (row[0], row[1], "abc123" in row[2], row[3]), ("s1", "pane-control-guard", False, '{"ops":["ListBuckets"]}'))
        check("ask join key", conn.execute("SELECT count(*) FROM asks WHERE input_hmac = ?",
                                           (hmac_of(load_key(path), {"command": "tuios send-text x"}),)).fetchone()[0], 1)
        ro = open_db(path, readonly=True)
        check("read-only open", ro is not None, True)
        try:
            ro.execute("INSERT INTO meta VALUES ('a', 'b')")
            check("read-only refuses writes", True, False)
        except sqlite3.Error:
            pass
        ro.close()

        repo_dir = os.path.join(tmp, "repo")
        os.makedirs(repo_dir)
        git, sha = _git_repo(repo_dir)
        gkey = load_key(path)

        def push(command, cwd=repo_dir):
            prompt, segs = build_record({"session_id": "s", "tool_name": "Bash", "tool_input": {"command": command},
                                         "cwd": cwd}, gkey)
            return prompt, segs

        cases = [
            ("git push", "main", "default", False, False),
            ("git push origin HEAD", "main", "default", False, False),
            ("git push -u origin feat/x", "feat/x", "feature", False, False),
            ("git push origin HEAD:refs/heads/release/2", "release/2", "protected", False, False),
            ("git push --force-with-lease origin feat/x", "feat/x", "feature", True, False),
            ("git push origin +feat/x:feat/x", "feat/x", "feature", True, False),
            ("git push origin --delete feat/x", "feat/x", "feature", False, True),
            ("git push origin :feat/x", "feat/x", "feature", False, True),
            ("git push origin refs/tags/v1", "refs/tags/v1", "protected", False, False),
            ("git push --all", "*", "protected", False, False),
            ("cd " + repo_dir + " && git checkout -b topic && git push", "topic", "feature", False, False),
        ]
        for command, dst, cls, force, delete in cases:
            _, segs = push(command)
            seg = segs[-1]
            target = json.loads(seg["target"])
            check(command, (target["dst"], target["dst_class"], target["force"], target["delete"]),
                  (dst, cls, force, delete))
        _, segs = push("git push")
        target = json.loads(segs[0]["target"])
        check("push: remote and sha before", (target["remote"], target["dst_sha_before"]), ("origin", sha))
        check("push: scope", segs[0]["scope_key"], "repo=github.com/acme/repo|dst=default|force=0|delete=0")
        check("push: protected", is_protected_push(target, "feature"), True)
        check("push to feature is not protected", is_protected_push({"dst_class": "feature"}, "default"), False)
        check("unknown dst follows the branch", is_protected_push({"dst_class": "unknown"}, "default"), True)
        git("checkout", "-q", "--detach")
        _, segs = push("git push")
        check("detached bare push", json.loads(segs[0]["target"])["dst_class"], "unknown")
        _, segs = push("git push", "/nowhere/x")
        check("outside a repo", (segs[0]["scope_key"], segs[0]["repo"]), ("repo=none|dst=unknown|force=0|delete=0", None))
        _, segs = push("git reset --hard HEAD~1")
        check("branch family", segs[0]["scope_key"].endswith("|bc=detached"), True)
        _, segs = push("ls -la")
        check("generic scope", segs[0]["scope_key"], "repo=github.com/acme/repo")
        _, segs = push("cd $X && git push")
        check("uncertain", [s["ctx_uncertain"] for s in segs], [1])

        prompt, segs = push("git push --force origin feat/x")
        pid = store_record(conn, prompt, segs)
        conn.commit()
        check("stored", conn.execute("SELECT count(*) FROM prompt_segments WHERE prompt = ?", (pid,)).fetchone()[0], 1)
        check("repo upserted", conn.execute("SELECT repo_key, default_ref FROM repos").fetchall(),
              [("github.com/acme/repo", "main")])
        check("exact key differs by scope", segs[0]["ctx_input_hmac"] != push("git push --force origin feat/y")[1][0]["ctx_input_hmac"], True)
        prompt, segs = build_record({"session_id": "s", "tool_name": "Edit", "cwd": repo_dir,
                                     "tool_input": {"file_path": os.path.join(repo_dir, "sub", "a.py"), "new_string": "x"}}, gkey)
        check("edit target", (segs[0]["shape"], json.loads(segs[0]["target"])), ("Edit sub/a.py", {"path": "sub/a.py"}))
        check("edit scope", segs[0]["scope_key"], "repo=github.com/acme/repo|bc=detached|top=sub")
        prompt, segs = build_record({"session_id": "s", "tool_name": "WebFetch", "cwd": repo_dir,
                                     "tool_input": {"url": "https://docs.example.com/x"}}, gkey)
        check("webfetch scope", segs[0]["scope_key"], "host=docs.example.com")
        prompt, segs = build_record({"session_id": "s", "tool_name": "mcp__tuios__send_text", "cwd": repo_dir,
                                     "tool_input": {"session": "dotfiles", "text": "ls"}}, gkey)
        check("mcp", (prompt["mcp_server"], segs[0]["scope_key"]), ("tuios", "repo=github.com/acme/repo"))
        prompt, segs = build_record({"session_id": "s", "tool_name": "Bash", "cwd": repo_dir,
                                     "tool_input": {"command": "git push origin main"}}, gkey, partial={"branch": "x"})
        check("partial", (prompt["ctx_partial"], prompt["ts_prompt"], segs[0]["scope_key"], segs[0]["branch"]),
              (1, None, "partial", "x"))
        prompt, segs = build_record({"session_id": "s", "tool_name": "Bash", "cwd": repo_dir,
                                     "tool_input": {"command": "fnox exec -- aws s3 ls"}}, gkey, partial={"branch": None})
        check("partial with a wrapper", (segs[0]["family"], json.loads(segs[0]["target"])), ("aws s3 ls", {"via": ["fnox exec"]}))
        conn.close()
    finally:
        if saved is None:
            os.environ.pop("AGENT_DECISIONS_DB", None)
        else:
            os.environ["AGENT_DECISIONS_DB"] = saved
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"decision_log: {len(TABLE)} table, {len(EXTRA_SHAPES)} shape, {len(SECRETS)} redaction cases: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else 2)
