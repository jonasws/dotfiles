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
import re
import subprocess
import sys

REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "eu-west-1"
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from tmlpane import Pane, print_rerun  # noqa: E402
TML = pathlib.Path(__file__).with_name("watch-cfn-deployment.tml")

# Stack-level statuses that begin an operation; the latest one marks its start.
START = {"CREATE_IN_PROGRESS", "UPDATE_IN_PROGRESS", "DELETE_IN_PROGRESS", "IMPORT_IN_PROGRESS"}
# Failures CloudFormation reports as a consequence of another resource failing.
KNOCK_ON = re.compile(r"cancelled|Resource update cancelled|resource\(s\) failed to", re.I)
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


def ts(value):
    return datetime.datetime.fromisoformat(value) if value else None


def clock(t):
    return t.astimezone().strftime("%H:%M:%S") if t else "-"


def dur(seconds):
    seconds = int(seconds)
    return f"{seconds // 60}m {seconds % 60}s"


def state_of(status):
    if status.endswith("_IN_PROGRESS"):
        return "working"
    if "ROLLBACK" in status or status.endswith("_FAILED"):
        return "errored"
    return "done"


def role_of(status):
    if status.endswith("_FAILED") or ("ROLLBACK" in status and status.endswith("_COMPLETE")):
        return "error"
    if status.endswith("_IN_PROGRESS"):
        return "warning"
    if status.endswith("_COMPLETE"):
        return "success"
    return "mute"


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


def operation_events(stack):
    """Events of the latest operation, newest first, read page by page until its start."""
    events, token = [], None
    while True:
        page = aws("cloudformation", "describe-stack-events", "--stack-name", stack,
                   "--max-items", "100", *(["--starting-token", token] if token else []))
        for e in page.get("StackEvents", []):
            events.append(e)
            if (e["ResourceType"] == "AWS::CloudFormation::Stack" and e["LogicalResourceId"] == stack
                    and e["ResourceStatus"] in START):
                return events
        token = page.get("NextToken")
        if not token:
            return events


def build_state(stack, account):
    summary = aws("cloudformation", "describe-stacks", "--stack-name", stack)["Stacks"][0]
    status = summary["StackStatus"]
    events = operation_events(stack)
    start = ts(events[-1]["Timestamp"]) if events else None
    end = ts(events[0]["Timestamp"]) if events and not status.endswith("_IN_PROGRESS") else None

    latest = {}
    for e in events:
        if e["LogicalResourceId"] != stack:
            latest.setdefault(e["LogicalResourceId"], e)

    failures = [e for e in reversed(events) if e["ResourceStatus"].endswith("_FAILED")]
    root = next((e for e in failures if not KNOCK_ON.search(e.get("ResourceStatusReason", ""))),
                failures[0] if failures else None)

    def order(e):
        s = e["ResourceStatus"]
        return (0 if s.endswith("_FAILED") else 1 if s.endswith("_IN_PROGRESS") else 2,
                -ts(e["Timestamp"]).timestamp())

    resources = [{"id": e["LogicalResourceId"], "type": e["ResourceType"].removeprefix("AWS::"),
                  "status": e["ResourceStatus"], "role": role_of(e["ResourceStatus"]),
                  "time": clock(ts(e["Timestamp"])),
                  "reason": e.get("ResourceStatusReason", "")[:300]}
                 for e in sorted(latest.values(), key=order)]
    statuses = [r["status"] for r in resources]

    return {
        "stack": stack,
        "account": account,
        "status": status,
        "statusLabel": status.replace("_", " ").capitalize(),
        "statusState": state_of(status),
        "statusRole": role_of(status),
        "operation": events[-1]["ResourceStatus"].removesuffix("_IN_PROGRESS").lower() if events else "-",
        "reason": summary.get("StackStatusReason", ""),
        "rootCause": f"{root['LogicalResourceId']}: {root.get('ResourceStatusReason', '')}" if root else "",
        "started": clock(start),
        "finished": clock(end),
        "elapsed": dur(((end or datetime.datetime.now(datetime.timezone.utc)) - start).total_seconds()) if start else "-",
        "updated": clock(datetime.datetime.now(datetime.timezone.utc)),
        "inProgress": sum(s.endswith("_IN_PROGRESS") for s in statuses),
        "complete": sum(s.endswith("_COMPLETE") for s in statuses),
        "failed": sum(s.endswith("_FAILED") for s in statuses),
        "touched": len(resources),
        "resources": resources,
        "events": [{"key": e["EventId"], "time": clock(ts(e["Timestamp"])), "status": e["ResourceStatus"],
                    "role": role_of(e["ResourceStatus"]), "id": e["LogicalResourceId"], "reason": e.get("ResourceStatusReason", "")[:300]}
                   for e in events[:100]],
    }


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
