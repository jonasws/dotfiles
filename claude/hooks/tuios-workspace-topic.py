#!/usr/bin/env python3
"""Label the tuios workspace with this Claude Code session's topic.

Claude Code sets its topic with OSC 0, which tuios shows on the pane border and
the rail. An unnamed workspace takes only the name its active pane gave with
OSC 1, so this hook sends the pane's title again as OSC 1. A name given by hand
(prefix+T, set-workspace-name) still wins in tuios.

Hooks have no controlling terminal, so the sequence goes to TUIOS_PANE_TTY, the
pane's terminal device. It is sent only when the pane's OSC 1 name, as tuios
holds it, differs from the topic, to keep writes beside Claude Code's own output
to a minimum; a fish prompt before a resume resets that name, so the next hook
sends the topic again. When Claude Code exits, the
next fish prompt sends fish_tab_title as OSC 1 again.

Run on UserPromptSubmit and Stop, and on SessionStart for a resumed or forked
session, so its workspace is labelled before the first prompt. At SessionStart
the pane title may still be the shell's, so the topic comes from the pane's own
name or else the session's last title in the transcript. Prints nothing and
always exits 0.
"""

import json
import os
import subprocess
import sys
import unicodedata

MAX_LABEL = 60
GENERIC_TITLES = {"claude", "claude code"}
# Marks the workspace label of an agent running inside nono (nf-md-lock).
SANDBOX_MARK = "\U000f033e"


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


def pane_window(session, pane):
    out = subprocess.run(
        ["tuios", "list-windows", "-s", session, "--json"],
        capture_output=True, text=True, timeout=3, check=True,
    )
    for win in json.loads(out.stdout).get("windows") or []:
        if win.get("window_id") == pane:
            return win
    return {}


def transcript_title(path):
    """The session's last title: one set with /rename, else the generated one."""
    custom = ai = ""
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if '"custom-title"' not in line and '"ai-title"' not in line:
                    continue
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if entry.get("type") == "custom-title":
                    custom = entry.get("customTitle") or custom
                elif entry.get("type") == "ai-title":
                    ai = entry.get("aiTitle") or ai
    except OSError:
        pass
    return custom or ai


def main():
    pane = os.environ.get("TUIOS_PANE_ID")
    session = os.environ.get("TUIOS_SESSION")
    tty = os.environ.get("TUIOS_PANE_TTY")
    if not (pane and session and tty):
        return
    try:
        event = json.load(sys.stdin)
    except ValueError:
        event = {}

    win = pane_window(session, pane)
    if event.get("hook_event_name") == "SessionStart":
        title = win.get("custom_name") or transcript_title(event.get("transcript_path") or "")
    else:
        title = win.get("display_name") or win.get("title") or ""
    topic = normalize(title)
    if not topic or topic.lower() in GENERIC_TITLES:
        return
    if os.environ.get("NONO_CAP_FILE"):
        topic = f"{SANDBOX_MARK} {topic}"

    if win.get("icon_name") == topic:
        return

    fd = os.open(tty, os.O_WRONLY | os.O_NOCTTY)
    try:
        # One write, so the sequence cannot be split by Claude Code's output.
        os.write(fd, f"\x1b]1;{topic}\x07".encode())
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
