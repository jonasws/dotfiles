#!/usr/bin/env python3
"""Exa for agents in nono, with the API key and the fetch policy outside.

find-docs' exa.sh talks to this gate (EXA_API_BASE_URL), inside nono and out,
instead of api.exa.ai, which the nono profile denies outright. The gate holds the key, read
from the keychain item nono:exa, and passes on only two calls:

  POST /search    as asked. Results and their contents come from Exa's
                  index, not from a URL the agent chose.
  POST /contents  cache only (maxAgeHours -1). Exa never fetches a URL it has
                  not crawled before, so a URL that carries data out (an
                  attacker's host, a query string built from a secret) gets no
                  request at all. On a cache miss the gate asks in the agent's
                  tuios pane, showing the URL; a yes fetches those URLs live.

Everything else (agent runs, answers, research) is refused: those let Exa
fetch whatever it decides to.

It runs as a LaunchAgent (com.jonasws.nono-exa-gate.plist) on 127.0.0.1 only.
The pane is found from the TCP peer's process.
"""

import json
import os
import pathlib
import socketserver
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

HOME = pathlib.Path.home()
PORT = int(os.environ.get("EXA_GATE_PORT", "47811"))
UPSTREAM = os.environ.get("EXA_GATE_UPSTREAM", "https://api.exa.ai")
TUIOS = os.environ.get("TUIOS_BIN", str(HOME / ".local/bin/tuios"))
ASK_TIMEOUT_MS = 120_000
FETCH, NO = "Fetch live", "No"
_key = None


def api_key(refresh=False):
    global _key
    if _key is None or refresh:
        out = subprocess.run(["security", "find-generic-password", "-s", "nono", "-a", "exa", "-w"],
                             capture_output=True, text=True)
        _key = out.stdout.strip() or None
    return _key


def upstream(path, body):
    for attempt in (0, 1):
        req = urllib.request.Request(UPSTREAM + path, data=json.dumps(body).encode(), method="POST",
                                     headers={"Content-Type": "application/json",
                                              "x-api-key": api_key(refresh=attempt == 1) or ""})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            if e.code == 401 and attempt == 0:
                continue
            try:
                return e.code, json.loads(e.read() or b"{}")
            except ValueError:
                return e.code, {"error": f"Exa answered {e.code}"}
    return 502, {"error": "Exa refused the key in the keychain item nono:exa"}


def peer_pids(client_port):
    try:
        out = subprocess.run(["lsof", "-nP", "-t", f"-iTCP@127.0.0.1:{client_port}", "-sTCP:ESTABLISHED"],
                             capture_output=True, text=True)
    except OSError:
        return []
    return [int(p) for p in out.stdout.split() if p.isdigit() and int(p) != os.getpid()]


def ancestors(pid):
    pids = []
    while pid > 1 and len(pids) < 64:
        pids.append(pid)
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True)
        try:
            pid = int(out.stdout.strip())
        except ValueError:
            break
    return pids


def pane_of(client_port):
    for pid in peer_pids(client_port):
        params = {"pids": ancestors(pid)}
        try:
            params["sid"] = os.getsid(pid)
        except OSError:
            pass
        out = subprocess.run([TUIOS, "call", "resolve-pane", json.dumps(params)],
                             capture_output=True, text=True)
        try:
            pane = json.loads(out.stdout) if out.returncode == 0 else {}
        except ValueError:
            pane = {}
        if pane.get("window_id") and pane.get("session"):
            return pane["session"], pane["window_id"]
    return None, None


def describe(urls):
    u = urllib.parse.urlsplit(urls[0])
    shown = f"{u.scheme}://{u.netloc}{u.path}"
    if u.query:
        # The query is where data leaves; show its start and its size.
        shown += f"?{u.query[:40]}" + (f"… ({len(u.query)} chars)" if len(u.query) > 40 else "")
    more = f" (+{len(urls) - 1} more)" if len(urls) > 1 else ""
    text = f"Live fetch {shown}{more}"
    encoded = text.encode()
    return encoded[:157].decode(errors="ignore") + "..." if len(encoded) > 160 else text


def ask(urls, client_port):
    session, window = pane_of(client_port)
    argv = [TUIOS, "ask-human", "--json", "--timeout", str(ASK_TIMEOUT_MS), "-o", FETCH, "-o", NO]
    if session and window:
        argv += ["-s", session, "-w", window]
    argv.append(describe(urls))
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=ASK_TIMEOUT_MS / 1000 + 10)
        return json.loads(out.stdout or "{}").get("answer") == FETCH
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False


def contents(body, client_port):
    urls = body.get("urls") or body.get("ids") or []
    body = {k: v for k, v in body.items() if k not in ("livecrawl", "maxAgeHours", "ids")}
    body["urls"] = urls
    status, cached = upstream("/contents", {**body, "maxAgeHours": -1})
    if status != 200:
        return status, cached
    missed = [s["id"] for s in cached.get("statuses", []) if s.get("status") == "error"]
    if not missed:
        return status, cached
    if not ask(missed, client_port):
        for s in cached.get("statuses", []):
            if s.get("id") in missed:
                s["error"] = {"tag": "NOT_CACHED_AND_NOT_ALLOWED", "httpStatusCode": None}
        cached["gate"] = "Not in Exa's cache; the user did not allow a live fetch."
        return status, cached
    status, live = upstream("/contents", {**body, "urls": missed, "maxAgeHours": 0})
    if status != 200:
        return 200, cached
    keep = [r for r in cached.get("results", []) if r.get("url") not in missed and r.get("id") not in missed]
    cached["results"] = keep + live.get("results", [])
    cached["statuses"] = [s for s in cached.get("statuses", []) if s.get("id") not in missed] + live.get("statuses", [])
    return 200, cached


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("exa-gate: " + (fmt % args) + "\n")

    def reply(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path.rstrip("/")
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except ValueError:
            return self.reply(400, {"error": "body is not JSON"})
        if path == "/search":
            return self.reply(*upstream("/search", body))
        if path == "/contents":
            return self.reply(*contents(body, self.client_address[1]))
        self.reply(403, {"error": f"{path} is not available here: only search and cached page contents are"})

    def do_GET(self):
        self.reply(403, {"error": "only search and cached page contents are available here"})


class Server(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True


def main():
    with Server(("127.0.0.1", PORT), Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
