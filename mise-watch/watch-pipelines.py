"""Live TML view of CodePipelines in the build account, drawn in a tuios pane.

Needs build-account AWS credentials in the environment (the mise task runs it
under `fnox -P build exec`) and must run inside a tuios pane.

Positional arguments pick the actions to show on their own rows, as `Stage/Action`,
a bare action name, or a stage name for all its actions. Without any, it lists
every deploy stage/action of the pipelines and asks with `gum filter`, starting
from the previous choice for that environment.

Standalone, it opens its own surface. With --surface it patches the pipe_* keys
of an existing surface instead, which only works from the pane that opened it.
"""

import argparse
import datetime
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

REGION = "eu-west-1"
# The project prefix of the pipelines (cn-cx, cnops, cn-terminal); the mise.local.toml
# of each repo tree sets it.
PREFIX = os.environ.get("WATCH_PIPELINE_PREFIX")

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from tmlpane import Pane, print_rerun  # noqa: E402

ROLE = {
    "Succeeded": "success",
    "InProgress": "warning",
    "Failed": "error",
    "Stopped": "mute",
    "Stopping": "warning",
    "Superseded": "mute",
    "Abandoned": "mute",
}

TAB = """<col pad="1" gap="1">
  <row gap="2"><text role="dim">{prefix} build account · {region} · every {poll}s · updated</text><text>{{state.pipe_updated}}</text><text role="error">{{state.pipe_error}}</text></row>
  <list items="state.pipe_heads" as="h">
    <row gap="2"><text w="18">{{h.pipeline}}</text><badge w="12" role="{{h.role}}">{{h.status}}</badge><text role="dim">exec {{h.exec}} started {{h.started}} UTC</text></row>
  </list>
  <row gap="2"><text w="10" role="dim">PIPELINE</text><text w="30" role="dim">STAGE / ACTION</text><text w="12" role="dim">STATUS</text><text role="dim">DETAIL</text></row>
  <list items="state.pipe_rows" as="r">
    <row gap="2"><text w="10">{{r.pipeline}}</text><text w="30">{{r.stage}}</text><badge w="12" role="{{r.role}}">{{r.status}}</badge><text role="dim" wrap="none">{{r.detail}}</text></row>
  </list>
</col>"""


FOOTER = '''    <row gap="2">
      <button key="ctrl+c" on-press="close(null)">close</button>
    </row>
'''


def aws(*args):
    out = subprocess.run(
        ["aws", "--region", REGION, "--output", "json", *args],
        check=True, capture_output=True, text=True,
    )
    return json.loads(out.stdout)


ENVS = ("dev", "prod")
DEFAULT_WATCH = {"core", "CoreUsEast1Stack", "CargodeskWebappStack"}
# Pipeline plumbing stages: each already gets a stage row, so their actions add nothing.
PLUMBING = {"Source", "PrepareCdkSource", "Build", "UpdatePipeline", "Assets"}
LAST = pathlib.Path(os.environ.get("XDG_STATE_HOME") or pathlib.Path.home() / ".local/state") / "watch-pipelines-last.json"


def short_action(action):
    return action["actionName"].removesuffix(".Deploy")


def short_stage(stage):
    return stage["stageName"].removeprefix(f"{PREFIX}-")


def watched(stage, action, watch):
    return bool(watch & {short_action(action), f"{short_stage(stage)}/{short_action(action)}",
                         short_stage(stage), stage["stageName"]})


def list_actions(pipelines):
    keys = {}
    for name in pipelines:
        for s in aws("codepipeline", "get-pipeline-state", "--name", name)["stageStates"]:
            if s["stageName"] in PLUMBING:
                continue
            for a in s.get("actionStates", []):
                keys[f"{short_stage(s)}/{short_action(a)}"] = short_action(a)
    return keys


def load_last():
    try:
        return json.loads(LAST.read_text())
    except (OSError, ValueError):
        return {}


def has_tty():
    try:
        open("/dev/tty").close()
        return True
    except OSError:
        return False


def choose_actions(pipelines, scope):
    keys = list_actions(pipelines)
    last = load_last()
    if scope in last:
        selected = [k for k in keys if k in set(last[scope])]
    else:
        selected = [k for k, a in keys.items() if a in DEFAULT_WATCH]
    # Options go in on stdin, so gum reads keys from /dev/tty whatever stdin the task got.
    out = subprocess.run(
        ["gum", "filter", "--no-limit", "--header", "Stages/actions to show on their own rows (tab selects)",
         "--selected", ",".join(selected)],
        input="\n".join(keys), stdout=subprocess.PIPE, text=True,
    )
    if out.returncode != 0:
        sys.exit(out.returncode)
    chosen = [line for line in out.stdout.splitlines() if line]
    LAST.write_text(json.dumps({**last, scope: chosen}, indent=2) + "\n")
    return set(chosen)


def tuios(*args):
    return subprocess.run(["tuios", *args], check=True, capture_output=True, text=True).stdout


def badge(status):
    return {"status": status or "-", "role": ROLE.get(status or "", "dim")}


def now():
    return datetime.datetime.now().strftime("%H:%M:%S")


def poll(pipelines, watch):
    heads, rows = [], []
    for name in pipelines:
        short = name.removeprefix(f"{PREFIX}-")
        e = aws("codepipeline", "list-pipeline-executions", "--pipeline-name", name,
                "--max-items", "1")["pipelineExecutionSummaries"][0]
        current = e["pipelineExecutionId"]
        heads.append({"pipeline": name, "exec": current[:8], "started": str(e["startTime"])[11:19],
                      **badge(e["status"])})

        for s in aws("codepipeline", "get-pipeline-state", "--name", name)["stageStates"]:
            latest = s.get("latestExecution", {})
            if latest.get("pipelineExecutionId") != current:
                rows.append({"pipeline": short, "stage": s["stageName"], "status": "waiting", "role": "dim",
                             "detail": f"not reached yet (last run: {latest.get('status', '-')})"})
                continue

            actions = s.get("actionStates", [])
            status_of = lambda a: a.get("latestExecution", {}).get("status", "-")
            counts = {}
            for a in actions:
                counts[status_of(a)] = counts.get(status_of(a), 0) + 1
            detail = ", ".join(f"{v} {k.lower()}" for k, v in sorted(counts.items())) if len(actions) > 1 else ""
            failed = [a["actionName"] for a in actions if status_of(a) == "Failed"]
            running = [a["actionName"] for a in actions if status_of(a) == "InProgress"]
            if failed:
                detail += "; failed: " + ", ".join(failed)
            elif running and len(actions) > 1:
                detail += "; running: " + ", ".join(running[:3]) + (" …" if len(running) > 3 else "")
            rows.append({"pipeline": short, "stage": s["stageName"], "detail": detail, **badge(latest.get("status"))})

            for a in actions:
                if watched(s, a, watch):
                    rows.append({"pipeline": "", "stage": f"  └ {short_stage(s)}: {short_action(a)}",
                                 "detail": a.get("latestExecution", {}).get("summary", ""), **badge(status_of(a))})
    return heads, rows


def write_doc(poll_s):
    doc = (f'<tml version="1" title="{PREFIX} pipelines">\n'
           f'  <state>{{"pipe_heads": [], "pipe_rows": [], "pipe_updated": "starting", "pipe_error": ""}}</state>\n'
           f'  <col>\n  {TAB.format(prefix=PREFIX, region=REGION, poll=poll_s)}\n{FOOTER}  </col>\n</tml>\n')
    with tempfile.NamedTemporaryFile("w", suffix=".tml", delete=False) as f:
        f.write(doc)
    tuios("tml", "validate", f.name)
    return f.name


def watch_loop(patch, wait, pipelines, watch, poll_s):
    while True:
        try:
            heads, rows = poll(pipelines, watch)
            ops = [{"op": "replace", "path": "/pipe_heads", "value": heads},
                   {"op": "replace", "path": "/pipe_rows", "value": rows},
                   {"op": "replace", "path": "/pipe_updated", "value": now()},
                   {"op": "replace", "path": "/pipe_error", "value": ""}]
            line = " ".join(f"{h['pipeline']}={h['status']}" for h in heads)
        except subprocess.CalledProcessError as e:
            msg = ((e.stderr or str(e)).strip().splitlines() or ["?"])[-1][:120]
            ops = [{"op": "replace", "path": "/pipe_error", "value": f"poll failed: {msg}"},
                   {"op": "replace", "path": "/pipe_updated", "value": now()}]
            line = f"poll failed: {msg}"
        if not patch(ops):
            return 0
        print(f"{now()} {line}", flush=True)
        if wait(poll_s):
            return 0


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("actions", nargs="*",
                   help="Stage/Action, action or stage names to show on their own rows (default: choose with gum)")
    p.add_argument("--env", choices=ENVS, default="prod", help="watch PREFIX-core-ENV and PREFIX-apps-ENV")
    p.add_argument("--pipelines", help=argparse.SUPPRESS)
    p.add_argument("--poll", type=int, default=20, help="seconds between polls")
    p.add_argument("--no-focus", dest="focus", action="store_false", help="leave the focus on this pane")
    p.add_argument("--surface", help="patch this existing surface instead of opening one")
    p.add_argument("--list-actions", action="store_true", help="print every Stage/Action of the pipelines and exit")
    p.add_argument("--print-tab", action="store_true", help="print the TML tab body for embedding and exit")
    args = p.parse_args()
    if not PREFIX:
        raise SystemExit("WATCH_PIPELINE_PREFIX is not set; set it in the [env] of the tree's mise.local.toml.")

    if args.print_tab:
        print(TAB.format(prefix=PREFIX, region=REGION, poll=args.poll))
        return 0

    if args.pipelines:
        pipelines = [p for p in args.pipelines.split(",") if p]
        scope = ",".join(pipelines)
    else:
        pipelines = [f"{PREFIX}-core-{args.env}", f"{PREFIX}-apps-{args.env}"]
        scope = f"{PREFIX}:{args.env}"
    if args.list_actions:
        print("\n".join(list_actions(pipelines)))
        return 0
    if args.actions:
        watch = set(args.actions)
    elif has_tty():
        watch = choose_actions(pipelines, scope)
    else:
        watch = DEFAULT_WATCH
    if not args.pipelines:
        print_rerun("watch-pipelines", *sorted(watch), flags=("--env", args.env))
    if args.surface:
        def patch(ops):
            return subprocess.run(["tuios", "tml", "patch", args.surface, json.dumps(ops)],
                                  capture_output=True).returncode == 0
        try:
            return watch_loop(patch, lambda n: time.sleep(n), pipelines, watch, args.poll)
        except KeyboardInterrupt:
            return 130
    with Pane(write_doc(args.poll), args.focus) as pane:
        print(f"surface {pane.surface}; ctrl+c here or in the pane stops it", flush=True)
        return watch_loop(pane.patch, pane.wait, pipelines, watch, args.poll)
    return 130


if __name__ == "__main__":
    sys.exit(main())
