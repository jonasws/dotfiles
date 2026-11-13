"""Live TML view of a CloudFormation stack's latest operation, drawn in a tuios pane.

Uses whatever AWS credentials are in the environment and asks for the stack
with gum when none is given, unless exactly one stack has an operation in
progress. Stops polling once the operation has finished, and blocks until the
pane is closed.
"""

import argparse
import datetime
import json
import os
import pathlib
import subprocess
import sys

REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "eu-west-1"
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from tmlpane import Pane, print_rerun  # noqa: E402
TML = pathlib.Path(__file__).with_name("watch-cfn-deployment.tml")
STATE = pathlib.Path(__file__).with_name("watch-cfn-state.nu")

LISTED = ["CREATE_IN_PROGRESS", "CREATE_FAILED", "CREATE_COMPLETE", "ROLLBACK_IN_PROGRESS",
          "ROLLBACK_FAILED", "ROLLBACK_COMPLETE", "DELETE_IN_PROGRESS", "DELETE_FAILED",
          "UPDATE_IN_PROGRESS", "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS", "UPDATE_COMPLETE",
          "UPDATE_FAILED", "UPDATE_ROLLBACK_IN_PROGRESS", "UPDATE_ROLLBACK_FAILED",
          "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS", "UPDATE_ROLLBACK_COMPLETE",
          "REVIEW_IN_PROGRESS", "IMPORT_IN_PROGRESS", "IMPORT_COMPLETE",
          "IMPORT_ROLLBACK_IN_PROGRESS", "IMPORT_ROLLBACK_FAILED", "IMPORT_ROLLBACK_COMPLETE"]


def aws(*args):
    out = subprocess.run(["aws", "--region", REGION, "--output", "json", *args], check=True, capture_output=True, text=True)
    return json.loads(out.stdout) if out.stdout.strip() else {}


def clock(t):
    return t.astimezone().strftime("%H:%M:%S") if t else "-"


def choose_stack(account):
    stacks = aws("cloudformation", "list-stacks", "--stack-status-filter", *LISTED)["StackSummaries"]
    stacks = [s for s in stacks if not s.get("ParentId")]
    stacks.sort(key=lambda s: s.get("LastUpdatedTime") or s["CreationTime"], reverse=True)
    if not stacks:
        sys.exit(f"No stacks in account {account}.")
    busy = [s for s in stacks if s["StackStatus"].endswith("_IN_PROGRESS") and s["StackStatus"] != "REVIEW_IN_PROGRESS"]
    if len(busy) == 1:
        print(f"Only {busy[0]['StackName']} is in progress; watching it.", flush=True)
        return busy[0]["StackName"]
    width = max(len(s["StackName"]) for s in stacks)
    lines = [f"{s['StackName']:<{width}}  {s['StackStatus']}" for s in stacks]
    # Options go in on stdin, so gum reads keys from /dev/tty whatever stdin the task got.
    out = subprocess.run(["gum", "filter", "--header", f"CloudFormation stacks in {account}, latest first",
                          "--placeholder", "Type to filter"], input="\n".join(lines),
                         stdout=subprocess.PIPE, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit(out.returncode or 1)
    return out.stdout.split()[0]


def build_state(stack, account):
    out = subprocess.run(["nu", "--no-config-file", str(STATE), stack, account],
                         check=True, capture_output=True, text=True)
    return json.loads(out.stdout)


def tuios(*args):
    return subprocess.run(["tuios", *args], check=True, capture_output=True, text=True).stdout


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("stack", nargs="?", help="stack name (default: choose one with gum)")
    p.add_argument("--poll", type=int, default=5, help="seconds between polls")
    p.add_argument("--no-focus", dest="focus", action="store_false", help="leave the focus on this pane")
    args = p.parse_args()

    try:
        account = aws("sts", "get-caller-identity")["Account"]
    except subprocess.CalledProcessError:
        sys.exit("No working AWS credentials; run it under fnox exec -P <profile>.")
    stack = args.stack or choose_stack(account)
    print_rerun("watch-cfn-deployment", stack)

    with Pane(TML, args.focus) as pane:
        print(f"Watching {stack} (surface {pane.surface}); ctrl+c here or in the pane stops it", flush=True)
        while True:
            try:
                state = build_state(stack, account)
            except subprocess.CalledProcessError as e:
                msg = ((e.stderr or str(e)).strip().splitlines() or ["?"])[-1][:200]
                state = {"reason": f"poll failed: {msg}", "statusState": "unknown",
                         "updated": clock(datetime.datetime.now(datetime.timezone.utc))}
            if not pane.patch([{"op": "replace", "path": f"/{k}", "value": v} for k, v in state.items()]):
                return 0
            if state.get("statusState") in ("done", "errored"):
                print(f"{state['status']} after {state['elapsed']}; close the pane to exit.", flush=True)
                pane.wait()
                return 0
            if pane.wait(args.poll):
                return 0
    return 130


if __name__ == "__main__":
    sys.exit(main())
