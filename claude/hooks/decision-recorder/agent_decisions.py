#!/usr/bin/env python3
"""agent-decisions: read and maintain the log of answered permission prompts.

  init                   create the DB, its schema and the HMAC key (safe to repeat)
  log [--since 7d] [--outcome O] [--repo . | KEY] [--branch B] [--tool T] [--limit N]
                         prompts, newest first
  show ID                one prompt: context, segments, ask rows, transcript
  why [--since 30d]      prompts by reason_code and by the hook that asked
  doctor                 schema, key, row counts, prompts left pending

log, show and why open the DB read-only. The DB is $AGENT_DECISIONS_DB or
~/.local/share/agent-decisions/decisions.sqlite3. DESIGN.md has the
design; decision_log.py the storage. recall, top and import come later.
"""

import argparse
import glob
import importlib.util
import os
import re
import sys
import time


def load_module(name):
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


dl = load_module("decision_log")
UNITS = {"h": 3600, "d": 86400, "w": 7 * 86400}


def since_ms(text):
    if text in (None, "all"):
        return 0
    m = re.fullmatch(r"(\d+)([hdw])", text)
    if not m:
        raise SystemExit(f"--since takes 12h, 7d, 2w or all, not {text!r}")
    return int((time.time() - int(m.group(1)) * UNITS[m.group(2)]) * 1000)


def when(ms):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ms / 1000)) if ms else "-"


def open_ro():
    conn = dl.open_db(readonly=True)
    if conn is None:
        print(f"no decision log at {dl.db_path()}: run agent-decisions init", file=sys.stderr)
    return conn


def cmd_init(args):
    conn = dl.init_db()
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    conn.close()
    print(f"{dl.db_path()}: schema version {version}, key {dl.key_path()}")
    return 0


def cmd_rebuild(args):
    """Delete the rows made from transcripts alone and forget how far each
    transcript was read, so the next Stop reads them again with the current
    normalisation. Rows captured live keep their prompt-time context; only the
    family and shapes of their Bash segments are derived again, from the
    redacted command. The exact-match hash is left alone."""
    conn = dl.open_db()
    if conn is None:
        print("no database: run agent-decisions init", file=sys.stderr)
        return 1
    ids = [r[0] for r in conn.execute("SELECT id FROM prompts WHERE ctx_partial = 1")]
    conn.executemany("DELETE FROM prompt_segments WHERE prompt = ?", [(i,) for i in ids])
    conn.executemany("DELETE FROM prompts WHERE id = ?", [(i,) for i in ids])
    conn.execute("DELETE FROM meta WHERE k LIKE 'tx:%' OR k LIKE 'deleted:%'")
    reshaped = 0
    live = conn.execute("SELECT id, cwd, input_redacted FROM prompts WHERE tool_name = 'Bash' "
                        "AND input_redacted IS NOT NULL").fetchall()
    for pid, cwd, text in live:
        segs, _ = dl.analyse_bash(text, cwd or "")
        rows = conn.execute("SELECT seq FROM prompt_segments WHERE prompt = ? ORDER BY seq", (pid,)).fetchall()
        if len(rows) != len(segs):
            continue
        for (seq,), seg in zip(rows, segs):
            conn.execute("UPDATE prompt_segments SET family = ?, shape = ?, args_shape = ? WHERE prompt = ? AND seq = ?",
                         (seg["family"], seg["shape"], seg["args_shape"], pid, seq))
        reshaped += 1
    conn.commit()
    conn.close()
    print(f"deleted {len(ids)} transcript-only rows; transcripts are read again at the next Stop "
          f"(records up to 6 hours old). Re-derived the command shapes of {reshaped} live Bash rows.")
    return 0


def cmd_log(args):
    conn = open_ro()
    if conn is None:
        return 1
    where, params = ["coalesce(p.ts_prompt, p.ts_answer, 0) >= ?"], [since_ms(args.since)]
    if args.outcome:
        where.append("p.outcome = ?")
        params.append(args.outcome)
    if args.tool:
        where.append("p.tool_name = ?")
        params.append(args.tool)
    if args.branch:
        where.append("s.branch = ?")
        params.append(args.branch)
    if args.repo:
        key = args.repo
        if key == ".":
            repo = dl.gitctx.find_repo(os.getcwd())
            if repo is None:
                print("not inside a git repository", file=sys.stderr)
                return 1
            key = repo.info()["repo_key"]
        where.append("r.repo_key = ?")
        params.append(key)
    sql = ("SELECT p.id, coalesce(p.ts_prompt, p.ts_answer), coalesce(p.outcome, 'pending'), p.tool_name, "
           "coalesce(s.args_shape, s.shape, p.tool_name), r.repo_key, s.branch "
           "FROM prompts p LEFT JOIN prompt_segments s ON s.prompt = p.id AND s.seq = 0 "
           "LEFT JOIN repos r ON r.id = s.repo_id WHERE " + " AND ".join(where) +
           " ORDER BY coalesce(p.ts_prompt, p.ts_answer) DESC LIMIT ?")
    for pid, ts, outcome, tool, shape, repo_key, branch in conn.execute(sql, params + [args.limit]):
        print(f"{pid:>6}  {when(ts)}  {outcome:<14} {tool:<10} {shape}  [{repo_key or '-'} {branch or '-'}]")
    return 0


def cmd_show(args):
    conn = open_ro()
    if conn is None:
        return 1
    conn.row_factory = lambda cur, row: dict(zip([c[0] for c in cur.description], row))
    p = conn.execute("SELECT * FROM prompts WHERE id = ?", (args.id,)).fetchone()
    if not p:
        print(f"no prompt {args.id}", file=sys.stderr)
        return 1
    for k, v in p.items():
        if k == "input_hmac":
            v = v.hex()[:16] + "..."
        elif k in ("ts_prompt", "ts_answer"):
            v = f"{v} ({when(v)})" if v else v
        if v is not None:
            print(f"{k:<16} {v}")
    for s in conn.execute("SELECT s.*, r.repo_key FROM prompt_segments s LEFT JOIN repos r ON r.id = s.repo_id "
                          "WHERE s.prompt = ? ORDER BY s.seq", (args.id,)):
        print(f"\nsegment {s['seq']}: {s['args_shape']}")
        for k in ("family", "shape", "eff_dir", "repo_key", "worktree", "branch", "branch_class", "head_sha", "upstream",
                  "upstream_sha", "target", "scope_key", "ctx_uncertain"):
            if s[k] is not None:
                print(f"  {k:<14} {s[k]}")
        if s["fetched_at"]:
            print(f"  {'fetched_at':<14} {when(s['fetched_at'])}")
    for a in conn.execute("SELECT hook, ts, reason, detail FROM asks WHERE session_id = ? AND input_hmac = ? ORDER BY ts",
                          (p["session_id"], p["input_hmac"])):
        print(f"\nasked by {a['hook']} at {when(a['ts'])}: {a['reason'] or ''} {a['detail'] or ''}".rstrip())
    found = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{p['session_id']}.jsonl"))
    if found:
        print(f"\ntranscript       {found[0]}")
    return 0


def cmd_why(args):
    conn = open_ro()
    if conn is None:
        return 1
    since = since_ms(args.since)
    base = "coalesce(p.ts_prompt, p.ts_answer, 0) >= ?"
    reasons = conn.execute(f"SELECT coalesce(p.reason_code, 'unknown'), count(*) FROM prompts p WHERE {base} "
                           "GROUP BY 1 ORDER BY 2 DESC", (since,)).fetchall()
    for reason, count in reasons:
        top = conn.execute(f"SELECT coalesce(s.family, p.tool_name), count(*) FROM prompts p "
                           f"LEFT JOIN prompt_segments s ON s.prompt = p.id AND s.seq = 0 "
                           f"WHERE {base} AND coalesce(p.reason_code, 'unknown') = ? GROUP BY 1 ORDER BY 2 DESC LIMIT 3",
                           (since, reason)).fetchall()
        print(f"{reason:<28} {count:>5}   " + ", ".join(f"{f} {n}" for f, n in top))
    hooks = conn.execute(f"SELECT a.hook, count(DISTINCT p.id) FROM prompts p JOIN asks a ON a.session_id = p.session_id "
                         f"AND a.input_hmac = p.input_hmac WHERE {base} GROUP BY 1 ORDER BY 2 DESC", (since,)).fetchall()
    for hook, count in hooks:
        print(f"{'hook ' + hook:<28} {count:>5}")
    if not reasons:
        print("no prompts in that window")
    return 0


def cmd_doctor(args):
    problems = 0
    path = dl.db_path()
    print(f"db               {path}")
    if not os.path.exists(path):
        print("                 missing: run agent-decisions init")
        return 1
    conn = dl.open_db(readonly=True)
    version = None
    if conn is not None:
        version = conn.execute("PRAGMA user_version").fetchone()[0]
    print(f"schema           {'version ' + str(version) if conn is not None else 'missing or not version ' + str(dl.SCHEMA_VERSION)}")
    if conn is None:
        return 1
    key = dl.load_key()
    mode = oct(os.stat(dl.key_path()).st_mode & 0o777) if key else "-"
    print(f"key              {'present, mode ' + mode if key else 'MISSING: hooks record nothing'}")
    problems += 0 if key and mode == "0o600" else 1
    print(f"journal          {conn.execute('PRAGMA journal_mode').fetchone()[0]}, {os.path.getsize(path) // 1024} KB")
    counts = conn.execute("SELECT coalesce(outcome, 'pending'), count(*) FROM prompts GROUP BY 1 ORDER BY 2 DESC").fetchall()
    print("rows             " + (", ".join(f"{o} {n}" for o, n in counts) or "none yet"))
    old = conn.execute("SELECT count(*) FROM prompts WHERE outcome IS NULL AND ts_prompt < ?",
                       (int((time.time() - 86400) * 1000),)).fetchone()[0]
    print(f"pending > 1 day  {old}" + ("   (the reconciler isn't resolving prompts, or the sweep hasn't run)" if old else ""))
    problems += 1 if old else 0
    last = conn.execute("SELECT max(ts_answer) FROM prompts WHERE outcome_via = 'transcript'").fetchone()[0]
    print(f"permissionDecision seen: " + (f"last answer from the transcript {when(last)}" if last
                                          else "no permissionDecision seen since the log started"))
    sweep = conn.execute("SELECT v FROM meta WHERE k = 'last_sweep'").fetchone()
    print(f"last sweep       {when(int(sweep[0])) if sweep and sweep[0].isdigit() else 'never'}")
    return 1 if problems else 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="agent-decisions", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init").set_defaults(func=cmd_init)
    p = sub.add_parser("log")
    p.add_argument("--since", default="7d")
    p.add_argument("--outcome", choices=dl.OUTCOMES)
    p.add_argument("--repo", help="a repo key, or . for the repo of the current directory")
    p.add_argument("--branch")
    p.add_argument("--tool")
    p.add_argument("--limit", type=int, default=50)
    p.set_defaults(func=cmd_log)
    p = sub.add_parser("show")
    p.add_argument("id", type=int)
    p.set_defaults(func=cmd_show)
    p = sub.add_parser("why")
    p.add_argument("--since", default="30d")
    p.set_defaults(func=cmd_why)
    sub.add_parser("doctor").set_defaults(func=cmd_doctor)
    sub.add_parser("rebuild").set_defaults(func=cmd_rebuild)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
