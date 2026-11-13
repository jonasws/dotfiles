#!/usr/bin/env python3
"""Name each workspace of a tuios session after what runs in it.

A workspace takes, in order:

1. the topic of an agent pane on it: the focused pane when it is an agent,
   else the first agent pane in reading order;
2. the terminal title of a shell pane on it (fish_title's `cmd · repo@branch`):
   the focused pane, else the first pane in reading order.

tuios records no provenance for a workspace name (its workspace-renamed event
does not say who renamed), so the script keeps its own, per session and
workspace: `written`, the last name it set, and `manual`. A live name that is
neither empty nor `written` was given by hand, by any route (prefix+T, the CLI,
MCP, herdr's tab.rename, tmux rename-window). The workspace is then marked
manual and left alone until its name is cleared (`tuios set-workspace-name N`
with no name), which hands it back.

Runs are serialized with a lock, so overlapping hooks never see each other's
half-done write. A workspace with no record (a lost state file, a renamed
session) is adopted only while its name is empty or already what the script
would write.

Run by the daemon's [hooks] in config.toml with TUIOS_SESSION_ID set, or by
hand: workspace-names.py [--dry-run] [--delay SECONDS] [--all | SESSION...]

Consider retiring this script and its hooks if Gaurav-Gosain/tuios#2077 is
merged: tuios would then label an unnamed workspace with its active pane's
OSC 1 name, which fish_tab_title sets to repo@branch, and a stored name would
win as a hand rename does here. Check first what would be lost: #2077 reads
OSC 1 only, so an agent's topic (OSC 0) would no longer name its workspace.
"""

import argparse
import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
import unicodedata

MAX_LABEL = 60
GENERIC_AGENT_TITLES = {"claude", "claude code", "codex", "gemini", "opencode", "pi", "amp"}

STATE_PATH = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "tuios",
    "workspace-names.json",
)


def tuios_bin():
    return (
        os.environ.get("TUIOS_BIN")
        or shutil.which("tuios")
        or os.path.expanduser("~/.local/bin/tuios")
    )


def tuios(*args):
    out = subprocess.run(
        [tuios_bin(), *args], capture_output=True, text=True, timeout=10, check=True
    )
    return out.stdout


def tuios_json(*args):
    return json.loads(tuios(*args, "--json"))


def normalize(title):
    """Drop control characters and the status glyphs harnesses put in front."""
    if not title:
        return ""
    text = "".join(c for c in title if unicodedata.category(c)[0] != "C").strip()
    while text and ord(text[0]) > 127 and (
        unicodedata.category(text[0]).startswith("S") or 0x2800 <= ord(text[0]) <= 0x28FF
    ):
        text = text[1:].lstrip()
    if len(text) > MAX_LABEL:
        text = text[: MAX_LABEL - 1].rstrip() + "…"
    return text


def reading_order(windows):
    return sorted(windows, key=lambda w: (w.get("y") or 0, w.get("x") or 0))


def agent_topic(win, agent):
    topic = normalize(win.get("display_name") or win.get("title") or agent.get("name"))
    if topic.lower() in GENERIC_AGENT_TITLES or topic == win.get("foreground_cmd"):
        return ""
    return topic


def desired_label(windows, agents, focused_id):
    """windows: the panes of one workspace. agents: window_id -> agent row."""
    panes = [w for w in windows if not w.get("floating") and not w.get("minimized")]
    if not panes:
        return ""
    ordered = reading_order(panes)
    focused = next((w for w in panes if w["window_id"] == focused_id), None)

    candidates = ([focused] if focused else []) + ordered
    for win in candidates:
        agent = agents.get(win["window_id"])
        if agent:
            topic = agent_topic(win, agent)
            if topic:
                return topic

    shells = [w for w in candidates if w["window_id"] not in agents]
    for win in shells or candidates:
        title = normalize(win.get("display_name") or win.get("title"))
        if title:
            return title
    return ""


def load_state():
    try:
        with open(STATE_PATH) as f:
            data = json.load(f)
        if data.get("version") == 3 and isinstance(data.get("sessions"), dict):
            return data
    except (OSError, ValueError, AttributeError):
        pass
    return {"version": 3, "sessions": {}}


def save_state(state):
    tmp = f"{STATE_PATH}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, STATE_PATH)


def live_name(session, number):
    for ws in tuios_json("list-workspaces", "-s", session).get("workspaces") or []:
        if ws["workspace"] == number:
            return ws.get("name") or ""
    return ""


def claim(current, want, entry):
    """Whether the script may replace the live name, and the entry after."""
    if not current:
        return True, {"written": "", "manual": False}
    if entry.get("manual"):
        return False, entry
    if current == entry.get("written") or (not entry and current == want):
        return True, entry
    return False, {"written": entry.get("written", ""), "manual": True}


def sync_session(session, state, dry_run):
    windows = tuios_json("list-windows", "-s", session).get("windows") or []
    workspaces = tuios_json("list-workspaces", "-s", session).get("workspaces") or []
    agents = {
        a["window_id"]: a
        for a in (tuios_json("list-agents", "-s", session).get("agents") or [])
        if a.get("window_id")
    }
    records = state["sessions"].setdefault(session, {})

    for ws in workspaces:
        number, key = ws["workspace"], str(ws["workspace"])
        current = ws.get("name") or ""
        panes = [w for w in windows if w.get("workspace") == number]
        want = desired_label(panes, agents, ws.get("focused_window_id"))

        ours, entry = claim(current, want, records.get(key, {}))
        if ours and want != current and not dry_run:
            # A hand rename may have landed since the listing: look again.
            current = live_name(session, number)
            ours, entry = claim(current, want, entry)
        if not ours:
            if entry.get("manual") and not records.get(key, {}).get("manual"):
                print(f"{session} {number}: {current!r} was named by hand, left alone")
            records[key] = entry
            continue

        if want != current:
            print(f"{session} {number}: {current or '(unnamed)'} -> {want or '(unnamed)'}")
            if not dry_run:
                args = ["set-workspace-name", "-s", session, str(number)]
                tuios(*args, *([want] if want else []))
        if want or key in records:
            records[key] = {"written": want, "manual": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("sessions", nargs="*")
    parser.add_argument("--all", action="store_true", help="every session")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--delay", type=float, default=0.0,
        help="wait before reading, so a shell can redraw its title after a command",
    )
    args = parser.parse_args()

    if args.all:
        sessions = [s["name"] for s in json.loads(tuios("list-sessions", "--json"))]
    else:
        sessions = args.sessions or [os.environ.get("TUIOS_SESSION_ID", "")]
    sessions = [s for s in sessions if s]
    if not sessions:
        print("no session: pass one, --all, or set TUIOS_SESSION_ID", file=sys.stderr)
        return 2

    if args.delay > 0:
        time.sleep(args.delay)

    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    with open(STATE_PATH + ".lock", "w") as lock:
        # Hooks fire in bursts (a new pane is a new-window and a focus change);
        # one run at a time keeps `written` in step with the live name.
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load_state()
        for session in sessions:
            try:
                sync_session(session, state, args.dry_run)
            except (subprocess.SubprocessError, ValueError, KeyError) as err:
                print(f"{session}: {err}", file=sys.stderr)
        if not args.dry_run:
            save_state(state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
