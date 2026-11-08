"""Live TML view of an ECS service's most recent service deployment, drawn in a tuios pane.

Uses whatever AWS credentials are in the environment, finds the cluster itself,
and asks for the service with gum when none is given. Stops polling once the
deployment has finished, and blocks until the pane is closed.
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
TML = pathlib.Path(__file__).with_name("watch-ecs-deployment.tml")

LABELS = {
    "PENDING": "Deployment pending", "IN_PROGRESS": "Rolling out",
    "SUCCESSFUL": "Deployment succeeded", "STOPPED": "Deployment stopped",
    "STOP_REQUESTED": "Stop requested", "ROLLBACK_REQUESTED": "Rollback requested",
    "ROLLBACK_IN_PROGRESS": "Rolling back", "ROLLBACK_SUCCESSFUL": "Rolled back",
    "ROLLBACK_FAILED": "Rollback failed",
}
FINAL = {"SUCCESSFUL", "STOPPED", "ROLLBACK_SUCCESSFUL", "ROLLBACK_FAILED"}


def aws(*args):
    out = subprocess.run(["aws", "--region", REGION, "--output", "json", *args], check=True, capture_output=True, text=True)
    return json.loads(out.stdout) if out.stdout.strip() else {}


def ts(value):
    return datetime.datetime.fromisoformat(value) if value else None


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def clock(t):
    return t.astimezone().strftime("%H:%M:%S") if t else "-"


def dur(seconds):
    seconds = int(seconds)
    return f"{seconds // 60}m {seconds % 60}s"


def list_services():
    """Every service in the account, as {service name: cluster ARN}."""
    services = {}
    for cluster in aws("ecs", "list-clusters")["clusterArns"]:
        for arn in aws("ecs", "list-services", "--cluster", cluster)["serviceArns"]:
            services.setdefault(arn.rsplit("/", 1)[-1], cluster)
    return services


def choose_service(services, account):
    # Options go in on stdin, so gum reads keys from /dev/tty whatever stdin the task got.
    out = subprocess.run(["gum", "filter", "--header", f"ECS services in {account} ({REGION})",
                          "--placeholder", "Type to filter"], input="\n".join(sorted(services)),
                         stdout=subprocess.PIPE, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit(out.returncode or 1)
    return out.stdout.strip()


class Watch:
    def __init__(self, service, cluster):
        self.service, self.cluster = service, cluster
        self.revisions = {}
        self.history = []

    def revision(self, arn):
        if arn not in self.revisions:
            rev = aws("ecs", "describe-service-revisions", "--service-revision-arns", arn)["serviceRevisions"][0]
            self.revisions[arn] = {
                "taskDef": rev["taskDefinition"].rsplit("/", 1)[-1],
                "images": ", ".join(c["image"].rsplit("/", 1)[-1] for c in rev.get("containerImages", [])),
            }
        return self.revisions[arn]

    def state(self):
        listed = aws("ecs", "list-service-deployments", "--cluster", self.cluster, "--service", self.service,
                     "--max-results", "10")["serviceDeployments"]
        if not listed:
            return {"status": "NONE", "statusLabel": "No service deployments in the last 90 days",
                    "statusState": "idle", "updated": clock(now())}
        latest = max(listed, key=lambda d: d["createdAt"])["serviceDeploymentArn"]
        d = aws("ecs", "describe-service-deployments", "--service-deployment-arns", latest)["serviceDeployments"][0]
        target = d.get("targetServiceRevision", {})
        rev = self.revision(target["arn"])
        events = aws("ecs", "describe-services", "--cluster", self.cluster,
                     "--services", self.service)["services"][0]["events"]

        status = d["status"]
        start = ts(d.get("startedAt") or d.get("createdAt"))
        end = ts(d.get("finishedAt") or d.get("stoppedAt"))
        sources = d.get("sourceServiceRevisions", [])
        breaker = d.get("deploymentCircuitBreaker", {})
        rollback = d.get("rollback")
        self.history = (self.history + [target.get("runningTaskCount", 0)])[-60:]
        since = start - datetime.timedelta(seconds=5)

        return {
            "service": self.service,
            "cluster": self.cluster.rsplit("/", 1)[-1],
            "status": status,
            "statusLabel": LABELS.get(status, status),
            "statusState": "done" if status == "SUCCESSFUL"
            else "errored" if "ROLLBACK" in status or "STOP" in status else "working",
            "reason": d.get("statusReason", ""),
            "started": clock(start),
            "finished": clock(end),
            "elapsed": dur(((end or now()) - start).total_seconds()),
            "updated": clock(now()),
            "requested": target.get("requestedTaskCount", 0),
            "running": target.get("runningTaskCount", 0),
            "pending": target.get("pendingTaskCount", 0),
            "oldRequested": sum(s.get("requestedTaskCount", 0) for s in sources),
            "oldRunning": sum(s.get("runningTaskCount", 0) for s in sources),
            "breaker": breaker.get("status", "-"),
            "breakerFailures": breaker.get("failureCount", 0),
            "breakerThreshold": breaker.get("threshold", 0),
            "rollback": f"{rollback.get('reason', '')} (from {clock(ts(rollback.get('startedAt')))})" if rollback else "",
            "alarms": d.get("alarms", {}).get("status", "-"),
            **rev,
            "deploymentId": d["serviceDeploymentArn"].rsplit("/", 1)[-1],
            "history": self.history,
            "events": [{"id": e["id"], "time": clock(ts(e["createdAt"])), "message": e["message"]}
                       for e in events if ts(e["createdAt"]) >= since][:40],
        }


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("service", nargs="?", help="ECS service name (default: choose one with gum)")
    p.add_argument("--poll", type=int, default=10, help="seconds between polls")
    p.add_argument("--no-focus", dest="focus", action="store_false", help="leave the focus on this pane")
    args = p.parse_args()

    try:
        account = aws("sts", "get-caller-identity")["Account"]
    except subprocess.CalledProcessError:
        sys.exit("No working AWS credentials; run it under fnox exec -P <profile>.")
    services = list_services()
    if not services:
        sys.exit(f"No ECS services in account {account} ({REGION}).")
    service = args.service or choose_service(services, account)
    if service not in services:
        sys.exit(f"No service named {service} in account {account}.")
    cluster = services[service]
    print_rerun("watch-ecs-deployment", service)
    watch = Watch(service, cluster)

    with Pane(TML, args.focus) as pane:
        print(f"Watching {service} on {cluster.rsplit('/', 1)[-1]} (surface {pane.surface}); "
              "ctrl+c here or in the pane stops it", flush=True)
        while True:
            try:
                state = watch.state()
            except subprocess.CalledProcessError as e:
                msg = ((e.stderr or str(e)).strip().splitlines() or ["?"])[-1][:200]
                state = {"reason": f"poll failed: {msg}", "statusState": "unknown", "updated": clock(now())}
            if not pane.patch([{"op": "replace", "path": f"/{k}", "value": v} for k, v in state.items()]):
                return 0
            if state.get("status") in FINAL or state.get("status") == "NONE":
                if state["status"] != "NONE":
                    print(f"{state['statusLabel']} after {state['elapsed']}; close the pane to exit.", flush=True)
                pane.wait()
                return 0
            if pane.wait(args.poll):
                return 0
    return 130


if __name__ == "__main__":
    sys.exit(main())
