#!/usr/bin/env python3
"""tuios broker: the cross-session part of tuios for agents in nono.

An agent pane in nono holds the read, write and task grants. tuios lets such a
pane reach only its own session, so mail to an agent in another repository's
session, listing the agents there, and starting an agent are refused with
`forbidden`. Inside nono, nono/shims/tuios sends exactly those refused calls
here, and this service makes them as you, outside every pane, under these rules:

  send-agent-message  delivered, as mail from the asking pane. Mail does not
                      type into a pane: the recipient wakes on a fixed line
                      and reads the body as data. --from and --attach are
                      refused (the daemon would read the file outside nono).
  list-agents         listed, names and states only; no pane contents.
  start-agent         claude or pi only, in a repository root, after you say
                      yes in the Inbox on the asking pane. The new agent runs
                      in nono like any other (tuios/shims), and --prompt
                      reaches it as mail from the asking pane.

Anything else is refused. Typing into another session's agents (queue,
ask-agent, send-text) stays out: that runs with the target's authority.

The caller is placed by the kernel: the peer pid of the socket, its session id
and its ancestors go to tuios's resolve-pane, as tuios places its own callers.
A caller in no pane is refused.

Protocol: one JSON line {"argv": [...], "cwd": "..."} in, one JSON line
{"rc": int, "stdout": str, "stderr": str} out, over a Unix socket in a
directory the sandbox can connect to but not write.
"""

import json
import os
import pathlib
import socket
import socketserver
import struct
import subprocess
import sys

HOME = pathlib.Path.home()
SOCKET_DIR = HOME / ".local/state/nono-broker"
SOCKET = SOCKET_DIR / "broker.sock"
TUIOS = os.environ.get("TUIOS_BIN", str(HOME / ".local/bin/tuios"))
SHIMS = HOME / "dotfiles/tuios/shims"
# The repository roots of the agent profile (nono/profiles/liflig-base.json).
REPO_ROOTS = [HOME / d for d in ("CX", "CNOPS", "CN-TERMINAL", "LIFLIG", "NSBNO")]
HARNESSES = {"claude", "pi"}
ASK_TIMEOUT_MS = 300_000
START_IT, NO = "Start it", "No"

# Flags each verb takes from an agent: name -> takes a value.
SEND_FLAGS = {"-s": True, "--session": True, "-w": True, "--window": True,
              "--subject": True, "--reply-to": True, "--select": True,
              "--confirm": True, "--yes": False, "--json": False}
LIST_FLAGS = {"-s": True, "--session": True, "--select": True, "--all": False,
              "--all-sessions": False, "--json": False}
START_FLAGS = {"-s": True, "--session": True, "--cwd": True, "--name": True,
               "--prompt": True, "--json": False, "--no-wait": False,
               "--print-id": False}


class Refused(Exception):
    pass


def tuios(argv, env=None, timeout=60):
    out = subprocess.run([TUIOS] + argv, capture_output=True, text=True,
                         timeout=timeout, env=env)
    return out.returncode, out.stdout, out.stderr


def parse(argv, flags):
    """Split argv into (flags dict, positionals), refusing unknown flags."""
    opts, args, i = {}, [], 0
    while i < len(argv):
        word = argv[i]
        if word == "--":
            args += argv[i + 1:]
            break
        name, eq, value = word.partition("=")
        if word.startswith("-") and word != "-":
            if name not in flags:
                raise Refused(f"{name} is not available across sessions")
            if flags[name]:
                if not eq:
                    i += 1
                    if i >= len(argv):
                        raise Refused(f"{name} needs a value")
                    value = argv[i]
                opts[name] = value
            else:
                opts[name] = True
        else:
            args.append(word)
        i += 1
    return opts, args


def unparse(opts):
    out = []
    for name, value in opts.items():
        out += [name] if value is True else [name, value]
    return out


def peer_pid(conn):
    if sys.platform == "darwin":
        return conn.getsockopt(0, 0x002)  # SOL_LOCAL, LOCAL_PEERPID
    creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    return struct.unpack("3i", creds)[0]


def ancestors(pid):
    pids = []
    while pid > 1 and len(pids) < 64:
        pids.append(pid)
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                             capture_output=True, text=True)
        try:
            pid = int(out.stdout.strip())
        except ValueError:
            break
    return pids


def place(pid):
    params = {"pids": ancestors(pid)}
    try:
        params["sid"] = os.getsid(pid)
    except OSError:
        pass
    rc, out, _ = tuios(["call", "resolve-pane", json.dumps(params)])
    try:
        pane = json.loads(out) if rc == 0 else {}
    except ValueError:
        pane = {}
    if not pane.get("window_id") or not pane.get("session"):
        raise Refused("the caller runs in no tuios pane")
    return pane["session"], pane["window_id"]


def repo_root(path):
    real = pathlib.Path(os.path.realpath(path))
    if not any(real == r or r in real.parents for r in REPO_ROOTS):
        raise Refused(f"{path} is not under a repository root")
    out = subprocess.run(["git", "-C", str(real), "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    top = out.stdout.strip()
    if out.returncode != 0 or pathlib.Path(top) != real:
        raise Refused(f"{path} is not the top of a git repository or worktree")
    return real


def send(argv, session, window):
    opts, args = parse(argv, SEND_FLAGS)
    if len(args) != 1:
        raise Refused("send-agent-message takes the message as one argument")
    subject = opts.get("--subject")
    opts["--subject"] = f"[{session}] {subject}" if subject else f"From {session}"
    opts["--subject"] = opts["--subject"][:120]
    return tuios(["send-agent-message"] + unparse(opts) + ["--from", window, "--", args[0]])


def list_agents(argv, session, window):
    opts, args = parse(argv, LIST_FLAGS)
    if args:
        raise Refused("list-agents takes no arguments here")
    return tuios(["list-agents"] + unparse(opts))


def start(argv, session, window, cwd):
    opts, args = parse(argv, START_FLAGS)
    if len(args) != 1 or args[0] not in HARNESSES:
        raise Refused("start-agent here starts claude or pi, by that name and with no arguments")
    agent = args[0]
    root = repo_root(opts.get("--cwd") or cwd)
    target = opts.get("-s") or opts.get("--session") or root.name
    question = f"Agent in {session} asks to start {agent} in {root.name} (session {target})"
    rc, out, _ = tuios(["ask-human", "--json", "-s", session, "-w", window,
                        "--timeout", str(ASK_TIMEOUT_MS), "-o", START_IT, "-o", NO,
                        question[:160]], timeout=ASK_TIMEOUT_MS / 1000 + 10)
    try:
        answer = json.loads(out or "{}").get("answer")
    except ValueError:
        answer = None
    if answer != START_IT:
        return 1, "", f"tuios: the user did not allow starting {agent} in {root.name}\n"

    # claude and pi resolve to tuios/shims, so the agent starts in nono.
    env = dict(os.environ, PATH=f"{SHIMS}:{HOME}/.local/bin:/opt/homebrew/bin:/usr/bin:/bin")
    launch = ["start-agent", agent, "-s", target, "--cwd", str(root), "--json"]
    if opts.get("--name"):
        launch += ["--name", opts["--name"]]
    if opts.get("--no-wait") and not opts.get("--prompt"):
        launch.append("--no-wait")
    rc, out, err = tuios(launch, env=env, timeout=180)
    if rc != 0 or not opts.get("--prompt"):
        return rc, out, err
    try:
        started = json.loads(out)
    except ValueError:
        return rc, out, err
    new = started.get("window_id")
    if new:
        mrc, _, merr = tuios(["send-agent-message", "-s", target, "-w", new, "--from", window,
                              "--subject", f"From {session}"[:120], "--", opts["--prompt"]])
        if mrc != 0:
            err += f"tuios: the agent started, but the prompt could not be sent as mail: {merr}"
    return rc, out, err


def handle(request, pid):
    argv = request.get("argv") or []
    if not argv or not all(isinstance(a, str) for a in argv):
        raise Refused("no command")
    session, window = place(pid)
    verb, rest = argv[0], argv[1:]
    if verb == "send-agent-message":
        return send(rest, session, window)
    if verb == "list-agents":
        return list_agents(rest, session, window)
    if verb == "start-agent":
        return start(rest, session, window, request.get("cwd") or "")
    raise Refused(f"{verb} is not available across sessions")


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        request = {}
        try:
            request = json.loads(self.rfile.readline() or b"{}")
            rc, out, err = handle(request, peer_pid(self.connection))
        except Refused as e:
            rc, out, err = 1, "", f"tuios: forbidden: {e}\n"
        except (ValueError, OSError, subprocess.SubprocessError) as e:
            rc, out, err = 1, "", f"tuios broker: {type(e).__name__}: {e}\n"
        sys.stderr.write(f"nono-broker: {request.get('argv', [''])[:1]} -> {rc}\n"
                         if isinstance(request, dict) else "")
        self.wfile.write((json.dumps({"rc": rc, "stdout": out, "stderr": err}) + "\n").encode())


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
