#!/usr/bin/env python3
"""Recorder for the permission prompts the user answered. Modes:

  capture    PermissionRequest hook: write a pending row (the call, its
             git context and target) before the prompt can be answered
  post       PostToolUse and PostToolUseFailure hook (async): when the call
             has a pending row, mark it approved and ran
  reconcile  Stop and SubagentStop hook (async): read the new part of the
             transcript and fill in the user's answer for pending rows
  sweep      SessionStart hook (async): expire and delete old rows, at most
             every 6 hours

It reads the hook JSON on stdin, prints nothing and always exits 0, so a
failure here never changes what a call does. The DB is never created here:
without one (agent-decisions init) every mode does nothing. DESIGN.md
has the reasoning; decision_log.py has the storage and normalisation.

The transcript is the source of the answer: every tool_result record carries a
permissionDecision whose source starts with user_ when the user answered a
prompt (user_temporary, user_permanent, user_reject, user_abort). A result
from the hook source whose call has a pending row is a tuios Inbox answer.
A prompt found in the transcript without a captured row gets a row of its own,
marked ctx_partial. An approved push to a protected branch is never kept.

python3 -I decision-recorder.py --self-test drives the four modes with
synthetic hook payloads and a synthetic transcript.
"""

import datetime
import importlib.util
import json
import os
import re
import sqlite3
import sys
import time

INBOX_DENY = "The user denied this from the tuios Inbox."
# Answered by the user by design, not permission decisions.
NOT_PERMISSIONS = {"AskUserQuestion"}
REWIND = 256 * 1024
FRESH_MS = 6 * 3600 * 1000
DAY_MS = 86400 * 1000
SWEEP_EVERY_MS = 6 * 3600 * 1000
TOMBSTONE_MS = 2 * DAY_MS


def load_log():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "decision_log.py")
    spec = importlib.util.spec_from_file_location("decision_log", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_ts(text):
    try:
        return int(datetime.datetime.fromisoformat(str(text).replace("Z", "+00:00")).timestamp() * 1000)
    except (ValueError, TypeError):
        return None


def meta_get(conn, k):
    row = conn.execute("SELECT v FROM meta WHERE k = ?", (k,)).fetchone()
    return row[0] if row else None


def meta_set(conn, k, v):
    conn.execute("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v", (k, str(v)))


def drop_prompt(conn, pid):
    conn.execute("DELETE FROM prompt_segments WHERE prompt = ?", (pid,))
    conn.execute("DELETE FROM prompts WHERE id = ?", (pid,))


def protected_approval(dl, conn, pid):
    """True when a stored push segment of the prompt goes to a protected destination."""
    for target, cls in conn.execute("SELECT target, branch_class FROM prompt_segments WHERE prompt = ? AND family = 'git push'",
                                    (pid,)).fetchall():
        try:
            if dl.is_protected_push(json.loads(target or "{}"), cls):
                return True
        except ValueError:
            pass
    return False


def capture(dl, conn, key, payload):
    if not payload.get("tool_name") or not isinstance(payload.get("tool_input"), dict):
        return
    prompt, segments = dl.build_record(payload, key)
    dl.store_record(conn, prompt, segments)
    conn.commit()


def exit_code_of(payload):
    texts = [payload.get("error")]
    response = payload.get("tool_response")
    if isinstance(response, dict):
        code = response.get("exit_code", response.get("exitCode"))
        if isinstance(code, int):
            return code
        texts += [response.get("stderr"), response.get("stdout"), response.get("error")]
    else:
        texts.append(response)
    for text in texts:
        m = re.match(r"\s*Exit code (-?\d+)", text) if isinstance(text, str) else None
        if m:
            return int(m.group(1))
    return None


def post(dl, conn, key, payload):
    tin = payload.get("tool_input")
    if not isinstance(tin, dict):
        return
    row = conn.execute(
        "SELECT id FROM prompts WHERE session_id = ? AND input_hmac = ? AND outcome IS NULL "
        "ORDER BY ts_prompt DESC LIMIT 1", (payload.get("session_id") or "", dl.hmac_of(key, tin))).fetchone()
    if not row:
        return
    pid = row[0]
    failed = payload.get("hook_event_name") == "PostToolUseFailure"
    try:
        conn.execute("UPDATE prompts SET tool_use_id = ?, ran = ?, exit_code = ?, outcome = 'approved', "
                     "outcome_via = 'post', ts_answer = ? WHERE id = ?",
                     (payload.get("tool_use_id"), 0 if failed else 1, exit_code_of(payload), dl.now_ms(), pid))
    except sqlite3.IntegrityError:
        return
    if protected_approval(dl, conn, pid):
        drop_prompt(conn, pid)
    else:
        conn.execute("UPDATE prompt_segments SET outcome = 'approved' WHERE prompt = ?", (pid,))
    conn.commit()


def flatten(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""


def outcome_of(pd, text, is_error):
    source, decision = pd.get("source") or "", pd.get("decision")
    if source == "user_temporary":
        return "approved"
    if source == "user_permanent":
        return "approved_always"
    if source == "user_reject":
        return "declined"
    if source == "user_abort":
        return "cancelled"
    if source == "hook":
        return "inbox_declined" if INBOX_DENY in text or decision == "reject" else "inbox_approved"
    return "approved" if decision == "accept" and not is_error else "declined"


APPROVALS = ("approved", "approved_always", "inbox_approved")


def reconcile_records(dl, conn, key, records, session_id, max_age_ms=None, stats=None):
    """Apply the answers in transcript records (dicts, in order) to the DB."""
    stats = stats if stats is not None else {}

    def bump(name):
        stats[name] = stats.get(name, 0) + 1

    uses = {}
    cutoff = None if max_age_ms is None else dl.now_ms() - max_age_ms
    for rec in records:
        message = rec.get("message") if isinstance(rec.get("message"), dict) else {}
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use" and block.get("id"):
                uses[block["id"]] = {"name": block.get("name") or "", "input": block.get("input")}
                continue
            if block.get("type") != "tool_result" or not isinstance(rec.get("permissionDecision"), dict):
                continue
            pd = rec["permissionDecision"]
            ts = parse_ts(rec.get("timestamp")) or dl.now_ms()
            if cutoff is not None and ts < cutoff:
                continue
            tuid = block.get("tool_use_id")
            if not tuid:
                continue
            bump("results")
            use = uses.get(tuid)
            if use and use["name"] in NOT_PERMISSIONS:
                bump("ignored")
                continue
            sid = rec.get("sessionId") or session_id or ""
            existing = conn.execute("SELECT id, outcome_via FROM prompts WHERE tool_use_id = ?", (tuid,)).fetchone()
            if conn.execute("SELECT 1 FROM meta WHERE k = ?", ("deleted:" + tuid,)).fetchone():
                bump("tombstoned")
                continue
            pid = None
            if existing:
                if existing[1] == "transcript":
                    bump("already")
                    continue
                pid = existing[0]
            elif use and isinstance(use["input"], dict):
                row = conn.execute(
                    "SELECT id FROM prompts WHERE session_id = ? AND input_hmac = ? AND outcome IS NULL "
                    "AND (ts_prompt IS NULL OR ts_prompt <= ?) ORDER BY ts_prompt DESC LIMIT 1",
                    (sid, dl.hmac_of(key, use["input"]), ts + 5000)).fetchone()
                pid = row[0] if row else None
            source = pd.get("source") or ""
            if pid is None and not source.startswith("user_"):
                bump("ignored")
                continue
            outcome = outcome_of(pd, flatten(block.get("content")), bool(block.get("is_error")))
            fields = (tuid, outcome, pd.get("grantScope"), pd.get("reasonCode"), pd.get("circuitBreaker"),
                      pd.get("ruleSource"), ts)
            if pid is None:
                if not use or not isinstance(use["input"], dict):
                    bump("no_tool_use")
                    continue
                payload = {"session_id": sid, "tool_name": use["name"], "tool_input": use["input"],
                           "cwd": rec.get("cwd") or ""}
                if outcome in APPROVALS:
                    full, full_segments = dl.build_record(payload, key)
                    if any(dl.is_protected_push(json.loads(s["target"] or "{}"), s["branch_class"])
                           for s in full_segments if s["family"] == "git push"):
                        meta_set(conn, "deleted:" + tuid, ts)
                        bump("deleted_protected")
                        continue
                prompt, segments = dl.build_record(payload, key, partial={"branch": rec.get("gitBranch")}, ts=ts)
                extra = dict(zip(("tool_use_id", "outcome", "grant_scope", "reason_code", "circuit_breaker", "rule_source",
                                  "ts_answer"), fields), outcome_via="transcript", prompt_id=rec.get("promptId"))
                prompt["prompt_id"] = rec.get("promptId")
                try:
                    dl.store_record(conn, prompt, segments, extra)
                except sqlite3.IntegrityError:
                    bump("already")
                    continue
                bump("created")
                continue
            conn.execute("UPDATE prompts SET tool_use_id = ?, outcome = ?, outcome_via = 'transcript', grant_scope = ?, "
                         "reason_code = ?, circuit_breaker = ?, rule_source = ?, ts_answer = ? WHERE id = ?",
                         fields + (pid,))
            if outcome in APPROVALS and protected_approval(dl, conn, pid):
                drop_prompt(conn, pid)
                meta_set(conn, "deleted:" + tuid, ts)
                bump("deleted_protected")
            else:
                conn.execute("UPDATE prompt_segments SET outcome = ? WHERE prompt = ?", (outcome, pid))
                bump("matched")
    conn.commit()
    return stats


def read_new_lines(conn, path):
    """Return (records, new offset) for the part of the transcript not read yet."""
    size = os.path.getsize(path)
    saved = meta_get(conn, "tx:" + path)
    offset = int(saved) if saved and saved.isdigit() else 0
    start = max(0, min(offset, size) - REWIND) if saved else 0
    with open(path, "rb") as f:
        f.seek(start)
        data = f.read()
    if start > 0:
        data = data[data.find(b"\n") + 1:] if b"\n" in data else b""
    end = data.rfind(b"\n") + 1
    records = []
    for line in data[:end].split(b"\n"):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            records.append(rec)
    return records, size - (len(data) - end)


def reconcile(dl, conn, key, payload, max_age_ms=FRESH_MS):
    path = payload.get("transcript_path")
    if not isinstance(path, str) or not os.path.isfile(path):
        return {}
    first_read = meta_get(conn, "tx:" + path) is None
    records, new_offset = read_new_lines(conn, path)
    stats = reconcile_records(dl, conn, key, records, payload.get("session_id"), max_age_ms if first_read else None)
    meta_set(conn, "tx:" + path, new_offset)
    conn.commit()
    return stats


def sweep(dl, conn, force=False):
    now = dl.now_ms()
    last = meta_get(conn, "last_sweep")
    if not force and last and last.isdigit() and now - int(last) < SWEEP_EVERY_MS:
        return False
    conn.execute("UPDATE prompts SET outcome = 'unresolved', outcome_via = 'sweep' WHERE outcome IS NULL AND ts_prompt < ?",
                 (now - DAY_MS,))
    conn.execute("UPDATE prompt_segments SET outcome = 'unresolved' WHERE outcome IS NULL AND prompt IN "
                 "(SELECT id FROM prompts WHERE outcome = 'unresolved')")
    when = "coalesce(ts_prompt, ts_answer, 0)"
    conn.execute(f"UPDATE prompts SET input_redacted = NULL WHERE input_redacted IS NOT NULL AND outcome IS NOT NULL AND "
                 f"{when} < ? - (SELECT text_days FROM ttl WHERE ttl.outcome = prompts.outcome) * {DAY_MS}", (now,))
    expired = f"outcome IS NOT NULL AND {when} < ? - (SELECT keep_days FROM ttl WHERE ttl.outcome = prompts.outcome) * {DAY_MS}"
    conn.execute(f"DELETE FROM prompt_segments WHERE prompt IN (SELECT id FROM prompts WHERE {expired})", (now,))
    conn.execute(f"DELETE FROM prompts WHERE {expired}", (now,))
    conn.execute("DELETE FROM asks WHERE ts < ?", (now - 365 * DAY_MS,))
    conn.execute("DELETE FROM meta WHERE k LIKE 'deleted:%' AND CAST(v AS INTEGER) < ?", (now - TOMBSTONE_MS,))
    meta_set(conn, "last_sweep", now)
    conn.commit()
    conn.execute("PRAGMA incremental_vacuum")
    return True


def run(mode, payload):
    dl = load_log()
    conn = dl.open_db()
    key = dl.load_key() if conn else None
    if conn is None or not key:
        return
    try:
        if payload.get("tool_name") in NOT_PERMISSIONS:
            pass
        elif mode == "capture":
            capture(dl, conn, key, payload)
        elif mode == "post":
            post(dl, conn, key, payload)
        elif mode == "reconcile":
            reconcile(dl, conn, key, payload)
        elif mode == "sweep":
            sweep(dl, conn)
    finally:
        conn.close()


# --- self-test ---------------------------------------------------------------------

def self_test():
    import shutil
    import subprocess
    import tempfile

    failures = 0

    def check(label, got, want):
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")

    dl = load_log()
    tmp = os.path.realpath(tempfile.mkdtemp(prefix="decision-recorder-"))
    db = os.path.join(tmp, "data", "d.sqlite3")
    env = dict(os.environ, AGENT_DECISIONS_DB=db)
    script = os.path.realpath(__file__)

    def hook(mode, payload, raw=None):
        proc = subprocess.run([sys.executable, "-I", script, mode], input=raw if raw is not None else json.dumps(payload),
                              env=env, capture_output=True, text=True)
        check(f"{mode} prints nothing and exits 0", (proc.returncode, proc.stdout, proc.stderr), (0, "", ""))

    def rows(sql, *args):
        conn = sqlite3.connect(db)
        try:
            return conn.execute(sql, args).fetchall()
        finally:
            conn.close()

    try:
        hook("capture", {"session_id": "s", "tool_name": "Bash", "tool_input": {"command": "ls"}, "cwd": tmp})
        check("no DB, no file", os.path.exists(os.path.dirname(db)), False)
        for mode in ("capture", "post", "reconcile", "sweep"):
            hook(mode, None, raw="not json")
            hook(mode, None, raw="[]")
        os.environ["AGENT_DECISIONS_DB"] = db
        dl.init_db(db).close()
        key = dl.load_key(db)
        for mode in ("capture", "post", "reconcile", "sweep"):
            hook(mode, {})
            hook(mode, {"session_id": "s", "tool_name": "Bash", "tool_input": "x", "transcript_path": "/nonexistent"})

        repo_dir = os.path.join(tmp, "repo")
        os.makedirs(repo_dir)
        git, sha = dl._git_repo(repo_dir)
        git("checkout", "-q", "-b", "feat/y")

        def call(n, command, cwd=repo_dir):
            return {"session_id": "s1", "transcript_path": os.path.join(tmp, "t.jsonl"), "cwd": cwd, "permission_mode": "auto",
                    "hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": {"command": command},
                    "prompt_id": "p" + str(n)}

        calls = {
            "A": call(1, "git push origin feat/y"), "B": call(2, "rm -r build"), "C": call(3, "git push origin main"),
            "E": call(5, "tuios send-text x"), "G": call(7, "mise run x"), "H": call(8, "make deploy"),
        }
        for payload in calls.values():
            hook("capture", payload)
        check("pending rows", rows("SELECT count(*), sum(outcome IS NULL), sum(ts_prompt IS NOT NULL) FROM prompts"), [(6, 6, 6)])
        check("segment rows", rows("SELECT count(*) FROM prompt_segments")[0][0], 6)
        check("captured context", rows("SELECT branch, branch_class, scope_key FROM prompt_segments WHERE family = 'git push' "
                                       "ORDER BY seq, prompt")[0],
              ("feat/y", "feature", "repo=github.com/acme/repo|dst=feature|force=0|delete=0"))

        stamp = datetime.datetime.now(datetime.timezone.utc)
        lines, counter = [], [0]

        def result(tuid, name, tin, source, grant=None, text="ok", error=False, cwd=repo_dir, with_use=True, extra=None):
            counter[0] += 1
            at = (stamp + datetime.timedelta(milliseconds=counter[0] * 10)).isoformat().replace("+00:00", "Z")
            if with_use:
                lines.append({"type": "assistant", "timestamp": at, "message": {"content": [
                    {"type": "tool_use", "id": tuid, "name": name, "input": tin}]}})
            pd = {"decision": "accept" if source != "user_reject" else "reject", "source": source}
            pd.update(extra or {})
            if grant:
                pd["grantScope"] = grant
            lines.append({"type": "user", "timestamp": at, "sessionId": "s1", "cwd": cwd, "gitBranch": "feat/y",
                          "promptId": "pp", "permissionDecision": pd,
                          "message": {"content": [{"type": "tool_result", "tool_use_id": tuid, "content": text,
                                                   "is_error": error}]}})

        result("tu-A", "Bash", calls["A"]["tool_input"], "user_temporary", "once",
               extra={"reasonCode": "rule:userSettings", "ruleSource": "userSettings"})
        result("tu-B", "Bash", calls["B"]["tool_input"], "user_reject", text="rejected", error=True,
               extra={"reasonCode": "safetyCheck", "circuitBreaker": "dangerousRemoval"})
        result("tu-C", "Bash", calls["C"]["tool_input"], "user_temporary", "once")
        result("tu-D", "Bash", {"command": "terraform plan"}, "user_permanent", "always")
        result("tu-E", "Bash", calls["E"]["tool_input"], "hook", text=INBOX_DENY, error=True)
        result("tu-F", "Bash", {"command": "ls"}, "config")
        result("tu-G", "Bash", calls["G"]["tool_input"], "user_abort")
        result("tu-I", "Bash", {"command": "git push origin main"}, "user_temporary", "once")
        result("tu-J", "Edit", {"file_path": os.path.join(repo_dir, "a.py")}, "user_temporary", "once")
        with open(os.path.join(tmp, "t.jsonl"), "w") as f:
            f.write("\n".join(json.dumps(r) for r in lines) + "\n" + '{"type": "user", "partial')
        offset_before = os.path.getsize(os.path.join(tmp, "t.jsonl"))
        hook("reconcile", calls["A"])

        def outcome(command):
            return rows("SELECT outcome, outcome_via, grant_scope, reason_code, circuit_breaker, rule_source, tool_use_id "
                        "FROM prompts WHERE input_redacted = ?", command)

        check("A approved", outcome("git push origin feat/y"),
              [("approved", "transcript", "once", "rule:userSettings", None, "userSettings", "tu-A")])
        check("B declined", outcome("rm -r build")[0][:5], ("declined", "transcript", None, "safetyCheck", "dangerousRemoval"))
        check("C protected push dropped", outcome("git push origin main"), [])
        check("C segments dropped", rows("SELECT count(*) FROM prompt_segments WHERE prompt NOT IN (SELECT id FROM prompts)"), [(0,)])
        check("D partial row", rows("SELECT outcome, ctx_partial, ts_prompt, grant_scope, tool_use_id FROM prompts "
                                    "WHERE input_redacted = 'terraform plan'"), [("approved_always", 1, None, "always", "tu-D")])
        check("D partial repo", rows("SELECT repo_id IS NOT NULL FROM prompt_segments WHERE family = 'terraform plan'"), [(1,)])
        check("D partial segment", rows("SELECT scope_key, branch, family, outcome FROM prompt_segments WHERE family = 'terraform plan'"),
              [("partial", "feat/y", "terraform plan", "approved_always")])
        check("E inbox declined", outcome("tuios send-text x")[0][:2], ("inbox_declined", "transcript"))
        check("F config ignored", outcome("ls"), [])
        check("G cancelled", outcome("mise run x")[0][0], "cancelled")
        check("I protected partial never stored", rows("SELECT count(*) FROM prompts WHERE tool_use_id = 'tu-I'"), [(0,)])
        check("J file tool partial", rows("SELECT tool_name, outcome, ctx_partial FROM prompts WHERE tool_use_id = 'tu-J'"),
              [("Edit", "approved", 1)])
        check("H still pending", rows("SELECT outcome FROM prompts WHERE input_redacted = 'make deploy'"), [(None,)])
        check("segments follow the outcome", rows("SELECT outcome FROM prompt_segments WHERE family = 'git push'"), [("approved",)])
        check("offset stops before the partial line",
              int(rows("SELECT v FROM meta WHERE k = ?", "tx:" + os.path.join(tmp, "t.jsonl"))[0][0]) < offset_before, True)
        count = rows("SELECT count(*) FROM prompts")[0][0]
        hook("reconcile", calls["A"])
        check("reconcile again changes nothing", rows("SELECT count(*) FROM prompts")[0][0], count)
        conn = sqlite3.connect(db)
        conn.execute("DELETE FROM meta WHERE k LIKE 'tx:%'")
        conn.commit()
        conn.close()
        hook("reconcile", calls["A"])
        check("a full reread is idempotent (tombstones, tool_use_id)", rows("SELECT count(*) FROM prompts")[0][0], count)

        post_payload = dict(calls["H"], hook_event_name="PostToolUse", tool_use_id="tu-H",
                            tool_response={"stdout": "done", "stderr": "", "interrupted": False})
        hook("post", dict(post_payload, tool_input={"command": "never prompted"}))
        check("post without a pending row writes nothing", rows("SELECT count(*) FROM prompts")[0][0], count)
        hook("post", post_payload)
        check("post marks the call", rows("SELECT outcome, outcome_via, ran, tool_use_id FROM prompts WHERE tool_use_id = 'tu-H'"),
              [("approved", "post", 1, "tu-H")])
        hook("post", post_payload)
        check("post twice is harmless", rows("SELECT count(*) FROM prompts")[0][0], count)
        hook("capture", call(9, "make fail"))
        hook("post", dict(call(9, "make fail"), hook_event_name="PostToolUseFailure", tool_use_id="tu-K",
                          error="Exit code 2\nboom"))
        check("post failure", rows("SELECT ran, exit_code, outcome FROM prompts WHERE tool_use_id = 'tu-K'"), [(0, 2, "approved")])
        hook("capture", call(10, "git push origin main"))
        hook("post", dict(call(10, "git push origin main"), hook_event_name="PostToolUse", tool_use_id="tu-L",
                          tool_response={"stdout": ""}))
        check("post drops a protected push", rows("SELECT count(*) FROM prompts WHERE tool_use_id = 'tu-L'"), [(0,)])
        lines.clear()
        with open(os.path.join(tmp, "t.jsonl"), "a") as f:
            f.write('": 1}\n')
        result("tu-H", "Bash", calls["H"]["tool_input"], "user_temporary", "once", with_use=False)
        with open(os.path.join(tmp, "t.jsonl"), "a") as f:
            f.write("\n".join(json.dumps(r) for r in lines) + "\n")
        hook("reconcile", calls["A"])
        check("transcript upgrades a post row", rows("SELECT outcome_via, grant_scope, ran FROM prompts WHERE tool_use_id = 'tu-H'"),
              [("transcript", "once", 1)])

        hook("capture", call(11, "old pending"))
        conn = sqlite3.connect(db)
        old = dl.now_ms() - 3 * DAY_MS
        conn.execute("UPDATE prompts SET ts_prompt = ? WHERE input_redacted = 'old pending'", (old,))
        conn.execute("INSERT INTO prompts (session_id, input_hmac, ts_prompt, tool_name, cwd, input_redacted, outcome) "
                     "VALUES ('s', x'00', ?, 'Bash', '/', 'stale text', 'approved')", (dl.now_ms() - 40 * DAY_MS,))
        conn.execute("INSERT INTO prompts (session_id, input_hmac, ts_prompt, tool_name, cwd, input_redacted, outcome) "
                     "VALUES ('s', x'00', ?, 'Bash', '/', 'ancient', 'cancelled')", (dl.now_ms() - 100 * DAY_MS,))
        conn.execute("INSERT INTO meta VALUES ('deleted:old', '1')")
        conn.execute("DELETE FROM meta WHERE k = 'last_sweep'")
        conn.commit()
        conn.close()
        hook("sweep", {})
        check("sweep: pending older than a day is unresolved",
              rows("SELECT outcome, outcome_via FROM prompts WHERE input_redacted = 'old pending'"), [("unresolved", "sweep")])
        check("sweep: text expired", rows("SELECT input_redacted FROM prompts WHERE ts_prompt < ? AND outcome = 'approved'",
                                          dl.now_ms() - 35 * DAY_MS), [(None,)])
        check("sweep: row past keep_days deleted", rows("SELECT count(*) FROM prompts WHERE input_redacted = 'ancient'"), [(0,)])
        check("sweep: tombstone pruned", rows("SELECT count(*) FROM meta WHERE k = 'deleted:old'"), [(0,)])
        conn = sqlite3.connect(db)
        conn.execute("UPDATE prompts SET outcome = NULL, outcome_via = NULL WHERE input_redacted = 'old pending'")
        conn.commit()
        conn.close()
        hook("sweep", {})
        check("sweep is throttled", rows("SELECT outcome FROM prompts WHERE input_redacted = 'old pending'"), [(None,)])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"decision-recorder: {failures} failed")
    return 1 if failures else 0


def main():
    if "--self-test" in sys.argv:
        return self_test()
    try:
        mode = sys.argv[1] if len(sys.argv) > 1 else ""
        payload = json.load(sys.stdin)
        if mode in ("capture", "post", "reconcile", "sweep") and isinstance(payload, dict):
            run(mode, payload)
    except BaseException:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
