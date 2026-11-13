#!/usr/bin/env python3
"""A Vim-style jump list over tuios workspaces.

An entry is one workspace of one session. A jump lands on the pane last
focused there, which tuios remembers per workspace; moving between panes side
by side in one workspace is not a jump.

  jumplist.py event         record where you are now (the plugin's event hooks)
  jumplist.py back [N]      jump N entries older, like Vim's ctrl+o
  jumplist.py forward [N]   jump N entries newer, like Vim's ctrl+i
  jumplist.py goto INDEX    jump to one entry (the tuios-jumplist tv channel's Enter)
  jumplist.py list          print the list for tv, newest first

Only `event` runs inside the plugin, which holds the read grant. The jumps run
from `shell` command keys and the tv popup with the person's own rights, since
select-workspace and switch-session need the admin grant from a plugin.

The recorder is event hooks rather than a startup process: tuios refuses a
live upgrade (tuios daemon upgrade) while any plugin command is running, so a
process that never exits would block every upgrade. A hook that loses its
place to a dropped event catches up on the next one, since each run records
where the person is now rather than what the event says.

Runs on the macOS system python3 (3.9), so no newer syntax.
"""

import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
from contextlib import contextmanager

PLUGIN_ID = "jonasws.jumplist"
MAX_ENTRIES = 100
PENDING_TTL = 2.0
# A workspace left sooner than this was passed through, not visited, as a
# browser records only the page you land on.
DWELL = 1.0
# Popups this setup opens by name; focusing one is not a visit.
SKIP_NAMES = {"jumplist"}

TUIOS = os.environ.get("TUIOS_BIN") or shutil.which("tuios") or "tuios"


def state_dir():
    d = os.environ.get("TUIOS_PLUGIN_STATE_DIR")
    if not d:
        base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        d = os.path.join(base, "tuios", "plugins", PLUGIN_ID)
    os.makedirs(d, exist_ok=True)
    return d


STATE = os.path.join(state_dir(), "jumplist.json")
LOCK = os.path.join(state_dir(), "jumplist.lock")


def empty_state():
    return {"entries": [], "cursor": -1, "pending": None}


@contextmanager
def locked_state(write=True):
    with open(LOCK, "a") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            with open(STATE) as f:
                st = json.load(f)
        except (OSError, ValueError):
            st = empty_state()
        yield st
        if write:
            tmp = STATE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(st, f)
            os.replace(tmp, STATE)


def tuios(*args):
    r = subprocess.run([TUIOS, *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("tuios %s: %s" % (" ".join(args), (r.stderr or r.stdout).strip()))
    return r.stdout


def tuios_json(*args):
    return json.loads(tuios(*args, "--json"))


def session_windows(session):
    """The panes of one session by window id, and its focused pane."""
    try:
        d = tuios_json("list-windows", "-s", session)
    except (RuntimeError, ValueError):
        return {}, None
    return {w["window_id"]: w for w in d.get("windows") or []}, d.get("focused_window_id")


def describe(session, win):
    return {
        "session": session,
        "window": win["window_id"],
        "name": win.get("display_name") or win.get("custom_name") or win.get("title") or "",
        "workspace": win.get("workspace") or 0,
        "cwd": win.get("cwd") or "",
    }


def skipped(win):
    return bool(
        win.get("floating") or win.get("popup") or win.get("scratch")
        or (win.get("custom_name") or "") in SKIP_NAMES
    )


def key(e):
    return (e["session"], e["workspace"])


def drop_where(st, pred):
    """Remove the entries pred matches, keeping the cursor on the same entry."""
    kept, cursor = [], st["cursor"]
    for i, e in enumerate(st["entries"]):
        if pred(e):
            if i <= st["cursor"]:
                cursor -= 1
            continue
        kept.append(e)
    st["entries"] = kept
    st["cursor"] = min(max(cursor, 0 if kept else -1), len(kept) - 1)


def visit(st, session, win):
    if skipped(win):
        return
    entry = describe(session, win)
    entries = st["entries"]
    here = entries[st["cursor"]] if 0 <= st["cursor"] < len(entries) else None

    pending = st.get("pending")
    if pending and time.time() - pending["t"] < PENDING_TTL:
        if here is not None and key(here) == key(entry):
            st["pending"] = None
            here.update(entry)
            here["t"] = 0  # chosen by a jump, so never passed through
        # A jump can pass through other workspaces (the session it switches
        # to shows its own first); none of them is a visit.
        return
    st["pending"] = None

    if here is not None and key(here) == key(entry):
        here.update(entry)
        return

    # A new visit drops the entries after the cursor, as in Vim, and the
    # workspace's older entry, so each workspace is in the list once.
    now = time.time()
    st["entries"] = entries[: st["cursor"] + 1]
    if here is not None and now - here.get("t", 0) < DWELL:
        st["entries"].pop()
        st["cursor"] -= 1
    drop_where(st, lambda e: key(e) == key(entry))
    entry["t"] = now
    st["entries"].append(entry)
    st["entries"] = st["entries"][-MAX_ENTRIES:]
    st["cursor"] = len(st["entries"]) - 1


def shown_sessions():
    """The sessions attached clients show."""
    try:
        return {c["session"] for c in tuios_json("list-clients") if c.get("session")}
    except (RuntimeError, ValueError):
        return set()


def prune(st):
    alive = alive_in(st["entries"])
    drop_where(st, lambda e: not alive(e))


def on_event():
    """One event hook: a workspace or session was focused, or one closed."""
    event = os.environ.get("TUIOS_PLUGIN_EVENT", "")
    session = os.environ.get("TUIOS_PLUGIN_SESSION", "")
    with locked_state() as st:
        if event.endswith(".closed"):
            prune(st)
            return
        if not session:
            return
        # A workspace shown in a session no client shows is not where you are.
        shown = shown_sessions()
        if shown and session not in shown:
            return
        # Hooks run concurrently and may land out of order, so read where the
        # session is now instead of trusting the event.
        windows, focused = session_windows(session)
        if focused in windows:
            visit(st, session, windows[focused])


def alive_in(entries):
    """A workspace is alive while it holds a pane that is not a popup."""
    alive = {}
    for s in {e["session"] for e in entries}:
        windows, _ = session_windows(s)
        alive[s] = {w.get("workspace") or 0 for w in windows.values() if not skipped(w)}
    return lambda e: e["workspace"] in alive.get(e["session"], set())


def show_workspace(entry):
    # tuios lands on the pane last focused in the workspace.
    tuios("select-workspace", "-s", entry["session"], str(entry["workspace"]))


def go(entry):
    # Show the workspace first, then switch: the client arrives on the right
    # pane instead of arriving and then moving (television/scripts/tuios-focus.sh).
    other = entry["session"] != os.environ.get("TUIOS_SESSION", "")
    try:
        show_workspace(entry)
    except RuntimeError:
        if not other:
            raise
        tuios("switch-session", entry["session"])
        show_workspace(entry)
        return
    if other:
        tuios("switch-session", entry["session"])


def mark_jump(st, index):
    st["cursor"] = index
    st["pending"] = {"window": st["entries"][index]["window"], "t": time.time()}
    return st["entries"][index]


def step(delta):
    with locked_state() as st:
        entries = st["entries"]
        if not entries:
            return
        alive = alive_in(entries)
        i, target, moved = st["cursor"], None, 0
        while moved < abs(delta):
            i += 1 if delta > 0 else -1
            if not 0 <= i < len(entries):
                break
            if alive(entries[i]):
                target, moved = i, moved + 1
        if target is None:
            return
        entry = mark_jump(st, target)
    go(entry)


def goto(index):
    with locked_state() as st:
        if not 0 <= index < len(st["entries"]):
            return
        entry = mark_jump(st, index)
    go(entry)


DIM, BOLD, CYAN, RESET = "\x1b[2m", "\x1b[1m", "\x1b[36m", "\x1b[0m"


def list_rows():
    """One row per entry, newest first: INDEX SESSION/WINDOW, then the label.

    The tv channel reads the first two words back with {strip_ansi|split: :N}.
    """
    with locked_state(write=False) as st:
        entries, cursor = st["entries"], st["cursor"]
    alive = alive_in(entries)
    home = os.path.expanduser("~")
    for i in range(len(entries) - 1, -1, -1):
        e = entries[i]
        if not alive(e):
            continue
        cwd = e["cwd"]
        if cwd.startswith(home):
            cwd = "~" + cwd[len(home):]
        here = i == cursor
        offset = "%+d" % (i - cursor) if not here else "0"
        print("%s%d %s/w%d%s %s%s%4s%s  %-22.22s %-4s %-36.36s %s%s%s" % (
            DIM, i, e["session"], e["workspace"], RESET,
            BOLD + CYAN if here else "", "▶" if here else " ", offset, RESET,
            e["session"], "w%d" % e["workspace"] if e["workspace"] else "",
            e["name"], DIM, cwd, RESET))


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    arg = argv[2] if len(argv) > 2 else ""
    if cmd == "event":
        on_event()
    elif cmd in ("back", "forward"):
        n = int(arg) if arg.isdigit() else 1
        step(-n if cmd == "back" else n)
    elif cmd == "goto" and arg.isdigit():
        goto(int(arg))
    elif cmd == "list":
        list_rows()
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
