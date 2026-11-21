#!/usr/bin/env python3
"""nono approval webhook -> tuios Inbox.

nono asks this service before an agent reaches a host that is not on the
profile's allowlist (and for any endpoint rule set to "approve"). It turns the
request into `tuios ask-human` on the agent's own pane, so the question shows in
that pane's tuios client and in the Inbox, and reaches your phone when you are
away. Your answer goes back to nono:

  Allow once          -> granted        (this connection only)
  Allow this session  -> allow_session  (same host and port until the agent exits)
  Deny                -> denied

Protocol: nono's unsigned approval webhook v1 over a Unix socket (one HTTP/1.1
POST, JSON body, JSON decision). The socket sits in a directory the sandbox
cannot write, which nono checks before it starts a session.

It runs as a LaunchAgent (nono/approvals/com.jonasws.nono-approvals.plist), not
from a pane: tuios only lets a caller outside every pane ask on behalf of
another pane. nono's before-hook (nono/hooks/agent-before.sh) records which pane
each nono session belongs to, since the request carries no process id.
"""

import json
import os
import pathlib
import socketserver
import subprocess
import sys
from http.server import BaseHTTPRequestHandler

HOME = pathlib.Path.home()
SOCKET_DIR = HOME / ".local/state/nono-approvals"
SOCKET = SOCKET_DIR / "approval.sock"
SESSIONS = HOME / ".local/state/nono-agent/sessions"
TUIOS = os.environ.get("TUIOS_BIN", str(HOME / ".local/bin/tuios"))

ALLOW_ONCE, ALLOW_SESSION, DENY = "Allow once", "Allow this session", "Deny"
DECISIONS = {ALLOW_ONCE: "granted", ALLOW_SESSION: "allow_session", DENY: "denied"}


def session_info(session_id):
    try:
        return json.loads((SESSIONS / f"{session_id}.json").read_text())
    except (OSError, ValueError):
        return {}


def describe(request, where):
    kind = request.get("capability_type")
    if kind == "network":
        what = f"reach {request.get('host')}:{request.get('port')}"
    elif kind == "endpoint":
        op = request.get("operation")
        what = f"{request.get('method')} {request.get('upstream')}{request.get('path')}"
        if op:
            what += f" ({op})"
    elif kind == "command":
        what = "run " + " ".join([request.get("command", "")] + list(request.get("args") or []))
    elif kind == "capability":
        what = f"{request.get('access', 'use')} {request.get('path')}"
    else:
        what = f"do {kind}"
    question = f"Agent in {where} wants to {what}" if where else f"An agent wants to {what}"
    encoded = question.encode()
    return encoded[:157].decode(errors="ignore") + "..." if len(encoded) > 160 else question


def ask(request, timeout_secs):
    info = session_info(request.get("session_id", ""))
    where = info.get("repo") or info.get("tuios_session") or ""
    argv = [TUIOS, "ask-human", "--json", "--timeout", str(max(5, timeout_secs - 5) * 1000)]
    if info.get("pane"):
        argv += ["-w", info["pane"]]
    if info.get("tuios_session"):
        argv += ["-s", info["tuios_session"]]
    for option in (ALLOW_ONCE, ALLOW_SESSION, DENY):
        argv += ["-o", option]
    argv.append(describe(request, where))
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=timeout_secs)
        answer = json.loads(out.stdout or "{}").get("answer", "")
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        return {"decision": "denied", "reason": f"tuios ask-human failed: {type(e).__name__}"}
    if answer in DECISIONS:
        decision = {"decision": DECISIONS[answer]}
        if answer == DENY:
            decision["reason"] = "denied in tuios"
        return decision
    return {"decision": "timeout"}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def address_string(self):
        return "unix"

    def log_message(self, fmt, *args):
        sys.stderr.write("nono-approvals: " + (fmt % args) + "\n")

    def do_POST(self):
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            request = body.get("request") or {}
            timeout = int(self.headers.get("X-Nono-Timeout-Secs", "60"))
            reply = ask(request, timeout)
        except (ValueError, TypeError) as e:
            reply = {"decision": "denied", "reason": f"bad request: {e}"}
        data = json.dumps(reply).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def main():
    SOCKET_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(SOCKET_DIR, 0o700)
    if SOCKET.exists():
        SOCKET.unlink()
    with Server(str(SOCKET), Handler) as server:
        os.chmod(SOCKET, 0o600)
        server.serve_forever()


if __name__ == "__main__":
    main()
