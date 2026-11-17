"""Record a tuios session headlessly with asciinema while playing a timeline of TML state patches.

One process records and drives, so the user approves a single command. Steps:
  {"patch": {"caption": "...", "sim/status": "..."}, "wait": 3}   replace state paths, then sleep
  {"run": ["cmd", "arg"], "wait": 1}                              run a command to completion
  {"wait": 2}                                                     sleep
"""
import argparse
import json
import subprocess
import sys
import time

CHROME = ["--dockbar-position", "hidden", "--border-style", "hidden", "--hide-clock", "--hide-scrollbar",
          "--hide-window-buttons", "--window-title-position", "hidden"]


def patch(surface, values):
    ops = [{"op": "replace", "path": "/" + k.lstrip("/"), "value": v} for k, v in values.items()]
    r = subprocess.run(["tuios", "tml", "patch", surface, json.dumps(ops)], capture_output=True, text=True)
    if r.returncode != 0:
        print("patch failed:", r.stdout.strip(), r.stderr.strip(), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("timeline")
    ap.add_argument("--surface", required=True)
    ap.add_argument("--session", required=True)
    ap.add_argument("--cast", required=True)
    ap.add_argument("--size", default="200x46")
    ap.add_argument("--title", default="")
    a = ap.parse_args()
    with open(a.timeline) as f:
        tl = json.load(f)

    if "setup" in tl:
        patch(a.surface, tl["setup"])
    attach = " ".join(["tuios", "attach", a.session] + CHROME)
    cmd = ["asciinema", "rec", "--headless", "--overwrite", "--window-size", a.size, "-q", "-c", attach, a.cast]
    if a.title:
        cmd[3:3] = ["-t", a.title]
    rec = subprocess.Popen(cmd)
    try:
        time.sleep(tl.get("lead_in", 3))
        for step in tl["steps"]:
            if "patch" in step:
                patch(a.surface, step["patch"])
            if "run" in step:
                subprocess.run(step["run"])
            time.sleep(step.get("wait", 0))
        time.sleep(tl.get("tail", 3))
    finally:
        subprocess.run(["tuios", "detach-client", "-s", a.session], capture_output=True)
        rec.wait(timeout=30)
    print("recorded", a.cast)


if __name__ == "__main__":
    main()
