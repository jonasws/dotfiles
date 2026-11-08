"""A TML surface in its own tuios pane, tied to the script that opened it.

The script blocks on the pane: closing the pane (ctrl+c in it) ends the script,
and the script ending for any reason (finished, ctrl+c, killed) closes the pane
and hands the focus back to the pane it was started from.

The pane opens next to the calling pane, in its tuios session and workspace
(from TUIOS_SESSION and TUIOS_WINDOW_ID), not wherever the focus is by then.
"""

import atexit
import json
import os
import shlex
import signal
import subprocess
import sys
import threading


def print_rerun(task, *picked, flags=()):
    """On exit, print the command that watches the same thing again, for copying.

    The picked names are highlighted in bold cyan when stderr is a terminal.
    """
    color = sys.stderr.isatty() and not os.environ.get("NO_COLOR")
    names = [f"\033[1;36m{shlex.quote(a)}\033[0m" if color else shlex.quote(a) for a in picked]
    line = " ".join([*(shlex.quote(a) for a in ["mise", "run", task, *flags]), *names])
    atexit.register(lambda: print(f"rerun this with: {line}", file=sys.stderr, flush=True))


def _interrupt(*_):
    raise KeyboardInterrupt


class Pane:
    def __init__(self, path, focus=True):
        self.caller = os.environ.get("TUIOS_WINDOW_ID")
        session = os.environ.get("TUIOS_SESSION")
        self.target = ["-s", session] if session else []
        where = list(self.target)
        if self.caller:
            info = self._tuios("get-window", self.caller, "--json", *self.target)
            try:
                where += ["--workspace", str(json.loads(info.stdout)["workspace"])]
            except (ValueError, KeyError, TypeError):
                pass
        self.proc = subprocess.Popen(["tuios", "tml", "show", str(path), "--pane", "--events", "--json", *where],
                                     stdout=subprocess.PIPE, text=True)
        try:
            opened = json.loads(self.proc.stdout.readline())
            self.surface, self.window = opened["surface"], opened["window_id"]
        except (ValueError, KeyError):
            self.proc.kill()
            raise SystemExit("Could not open the TML surface; run it from a tuios pane.")
        self.closed = threading.Event()
        threading.Thread(target=self._drain, daemon=True).start()
        self.focused = focus
        if focus:
            self._tuios("focus-window", self.window, *self.target)
        for sig in (signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, _interrupt)

    @staticmethod
    def _tuios(*args):
        return subprocess.run(["tuios", *args], capture_output=True, text=True)

    def _drain(self):
        # The event stream ends once the surface is closed, by anyone.
        for _ in self.proc.stdout:
            pass
        self.closed.set()

    def patch(self, ops):
        """Apply a JSON Patch; False once the surface is gone."""
        return not self.closed.is_set() and self._tuios("tml", "patch", self.surface, json.dumps(ops)).returncode == 0

    def wait(self, seconds=None):
        """Sleep up to SECONDS, or until the pane closes; True when it closed."""
        return self.closed.wait(seconds)

    def __enter__(self):
        return self

    def __exit__(self, kind, *_):
        if not self.closed.is_set():
            self._tuios("tml", "close", self.surface)
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        if self.focused and self.caller:
            self._tuios("focus-window", self.caller, *self.target)
        return kind is KeyboardInterrupt
