#!/usr/bin/env python3
"""Label the tuios workspace with this Claude Code session's topic.

Claude Code sets its topic with OSC 0, which tuios shows on the pane border and
the rail. An unnamed workspace takes only the name its active pane gave with
OSC 1, so this hook sends the pane's title again as OSC 1. A name given by hand
(prefix+T, set-workspace-name) still wins in tuios.

Hooks have no controlling terminal, so the sequence goes to TUIOS_PANE_TTY, the
pane's terminal device. Each topic is sent once per session and pane, to keep
writes beside Claude Code's own output to a minimum. When Claude Code exits, the
next fish prompt sends fish_tab_title as OSC 1 again.

Run on UserPromptSubmit and Stop. Prints nothing and always exits 0.
"""

import json
import os
import subprocess
import sys
import unicodedata

MAX_LABEL = 60
GENERIC_TITLES = {"claude", "claude code"}
STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "tuios",
    "osc1-topic",
)


def normalize(title):
    """Drop control characters and the status glyphs Claude Code puts in front."""
    text = "".join(c for c in title or "" if unicodedata.category(c)[0] != "C").strip()
    while text and ord(text[0]) > 127 and (
        unicodedata.category(text[0]).startswith("S") or 0x2800 <= ord(text[0]) <= 0x28FF
    ):
        text = text[1:].lstrip()
    if len(text) > MAX_LABEL:
        text = text[: MAX_LABEL - 1].rstrip() + "…"
    return text


def pane_title(session, pane):
    out = subprocess.run(
        ["tuios", "list-windows", "-s", session, "--json"],
        capture_output=True, text=True, timeout=3, check=True,
    )
    for win in json.loads(out.stdout).get("windows") or []:
        if win.get("window_id") == pane:
            return win.get("display_name") or win.get("title") or ""
    return ""


def main():
    pane = os.environ.get("TUIOS_PANE_ID")
    session = os.environ.get("TUIOS_SESSION")
    tty = os.environ.get("TUIOS_PANE_TTY")
    if not (pane and session and tty):
        return
    try:
        claude_session = json.load(sys.stdin).get("session_id") or ""
    except ValueError:
        claude_session = ""

    topic = normalize(pane_title(session, pane))
    if not topic or topic.lower() in GENERIC_TITLES:
        return

    state = os.path.join(STATE_DIR, pane)
    sent = f"{claude_session}\n{topic}"
    try:
        with open(state) as f:
            if f.read() == sent:
                return
    except OSError:
        pass

    fd = os.open(tty, os.O_WRONLY | os.O_NOCTTY)
    try:
        # One write, so the sequence cannot be split by Claude Code's output.
        os.write(fd, f"\x1b]1;{topic}\x07".encode())
    finally:
        os.close(fd)

    os.makedirs(STATE_DIR, exist_ok=True)
    with open(state, "w") as f:
        f.write(sent)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
