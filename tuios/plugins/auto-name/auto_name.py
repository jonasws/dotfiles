#!/usr/bin/env python3
"""Name agent panes after their topic, so the rail stops showing "claude 1".

Follows `window-retitled` events: Claude Code sets its topic as the window
title, and the rail ranks a name set with set-window above the title. A name
this plugin wrote is remembered in a marker file, so a later topic renames the
pane again, while a name given by hand is left alone. `tuios set-window --name ""`
hands a pane back.

Runs on the macOS system python3 (3.9), so no newer syntax.
"""

import json
import os
import re
import shutil
import subprocess
import time

TUIOS = os.environ.get("TUIOS_BIN") or shutil.which("tuios") or "tuios"
MAX_LEN = 40
# A shell title, the command, or tuios's "Terminal <id>" default is not a topic.
NOT_TOPICS = {"claude", "claude code", "shell"}
LEADING_GLYPHS = re.compile(r"^[^\w]+", re.UNICODE)


def marker_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    d = os.path.join(base, "tuios-auto-name")
    os.makedirs(d, exist_ok=True)
    return d


MARKERS = marker_dir()


def call(verb, params):
    r = subprocess.run([TUIOS, "call", verb, json.dumps(params)], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except ValueError:
        return None


def topic_of(title):
    """The title with the status glyph Claude Code puts ahead of it dropped."""
    return LEADING_GLYPHS.sub("", title or "")[:MAX_LEN].strip()


def agent(session, window):
    res = call("list-agents", {"session": session})
    agents = res.get("agents") if isinstance(res, dict) else res
    for a in agents or []:
        if a.get("window_id") == window:
            return a
    return None


def read_marker(window):
    try:
        with open(os.path.join(MARKERS, window)) as f:
            return f.read()
    except OSError:
        return ""


def write_marker(window, name):
    with open(os.path.join(MARKERS, window), "w") as f:
        f.write(name)


def rename(session, window, topic):
    a = agent(session, window)
    if not a or not a.get("harness_id"):
        return
    cwd_base = os.path.basename((a.get("cwd") or "").rstrip("/"))
    if topic == cwd_base or topic.lower() in NOT_TOPICS or topic.startswith("Terminal "):
        return

    win = call("get-window", {"session": session, "window": window})
    if not isinstance(win, dict):
        return
    custom = win.get("custom_name") or ""
    if custom == topic or (custom and custom != read_marker(window)):
        return

    if call("set-window", {"session": session, "window": window, "name": topic}) is not None:
        write_marker(window, topic)


def follow():
    # Claude Code retitles on every spinner frame; only a new topic is work.
    last = {}
    proc = subprocess.Popen(
        [TUIOS, "subscribe", "--types", "window-retitled,window-closed"],
        stdout=subprocess.PIPE, text=True, bufsize=1,
    )
    for line in proc.stdout:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        typ, window = ev.get("type"), ev.get("window") or ""
        if typ == "gap":
            # Missed retitles are not replayed here; the next one names the pane.
            last.clear()
        elif typ == "window-closed":
            last.pop(window, None)
            try:
                os.remove(os.path.join(MARKERS, window))
            except OSError:
                pass
        elif typ == "window-retitled" and window:
            topic = topic_of(ev.get("title"))
            if not topic or last.get(window) == topic:
                continue
            last[window] = topic
            rename(ev.get("session") or "", window, topic)
    proc.wait()


def main():
    while True:
        follow()
        time.sleep(2)


if __name__ == "__main__":
    main()
