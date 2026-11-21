#!/usr/bin/env python3
"""PreToolUse hook for the AWS MCP server's tools (matcher `^mcp__aws__`). It
stands in for ask rules, which would override its allow.

IAM does the limiting, not this hook. The proxy (claude/mcp-servers.json) signs
each call with one of the profiles in AWS_MCP_PROXY_PROFILES, the first one
unless the call passes `aws_profile`. The `-readonly` profiles hand out
credentials narrowed by STS GetScopedCredentials to control-plane reads
(aws/policies/readonly.json), so AWS itself refuses anything else a script
tries, however it is written. The hook only checks which credentials a call
will run with:

- run_script runs without asking when its profile is scoped read-only, and
  asks for any other profile (the `-agent` ones can write).
- A profile counts as read-only only when ~/.aws/config gives it a
  credential_process of `aws-scoped-credentials` whose every --policy is
  `readonly`. The name alone is not enough.
- get_presigned_url always asks, documentation, region and task-polling tools
  are allowed, and a tool the hook does not know asks.

It also rewrites positional call_boto3 arguments to keywords, which the sandbox
requires. When it asks, it saves the script to
~/.cache/claude/run-script/<pane>.py, which prefix+p in tuios opens read-only.

`python3 -I aws-mcp-guard.py --self-test` checks the cases at the bottom.
"""

import ast
import configparser
import json
import os
import shlex
import sys
import tempfile

TOOL_PREFIX = "mcp__aws__aws___"
SCRIPT_TOOLS = {"run_script", "run_script_readonly"}
SAFE_TOOLS = {
    "search_documentation", "read_documentation", "retrieve_skill",
    "list_regions", "get_regional_availability", "get_tasks",
}
SERVER = "aws"
READONLY_POLICY = "readonly"
SCOPER = "aws-scoped-credentials"


def proxy_profiles(claude_json=None):
    """The profiles the proxy was started with, default first, or [] when unknown."""
    path = claude_json or os.path.expanduser("~/.claude.json")
    try:
        with open(path) as f:
            servers = json.load(f).get("mcpServers") or {}
        return (servers[SERVER].get("env") or {}).get("AWS_MCP_PROXY_PROFILES", "").split()
    except (OSError, ValueError, KeyError, AttributeError):
        return []


def readonly_profile(profile, aws_config=None):
    """Why `profile` is scoped read-only, or None when it is not."""
    path = aws_config or os.environ.get("AWS_CONFIG_FILE") or os.path.expanduser("~/.aws/config")
    parser = configparser.RawConfigParser(comment_prefixes=(";", "#"), strict=False)
    try:
        parser.read(path)
        # Inside nono, AWS_CONFIG_FILE is the placeholder config that
        # nono/tools/gen-aws.py writes. The sandbox can only read it, and nono
        # re-signs each profile as the read-only host profile of that name.
        if parser.get(f"profile {profile}", "nono_scope", fallback="") == READONLY_POLICY:
            return f"profile {profile} is signed by nono as the read-only host profile"
        argv = shlex.split(parser.get(f"profile {profile}", "credential_process"))
    except (configparser.Error, ValueError):
        return None
    if not argv or os.path.basename(argv[0]) != SCOPER:
        return None
    policies = [argv[i + 1] for i, a in enumerate(argv[:-1]) if a == "--policy"]
    if policies and all(p == READONLY_POLICY for p in policies):
        return f"profile {profile} is scoped to the {READONLY_POLICY} policy"
    return None


def decide_tool(tool_name, tool_input, profiles=None, aws_config=None):
    """(decision, reason) for any tool on the aws MCP server."""
    name = tool_name[len(TOOL_PREFIX):] if tool_name.startswith(TOOL_PREFIX) else tool_name
    if name in SAFE_TOOLS:
        return "allow", f"{name} reads no account data"
    if name == "get_presigned_url":
        return "ask", "get_presigned_url hands out read or write access to an S3 object"
    if name not in SCRIPT_TOOLS:
        return "ask", f"{tool_name} is not a tool aws-mcp-guard knows"
    profiles = proxy_profiles() if profiles is None else profiles
    profile = tool_input.get("aws_profile") or (profiles[0] if profiles else None)
    if not isinstance(profile, str):
        return "ask", f"{name}: cannot tell which profile the proxy signs with"
    why = readonly_profile(profile, aws_config)
    if why:
        return "allow", f"{name}: {why}"
    return "ask", f"{name} runs with profile {profile}, which is not scoped read-only"


# call_boto3's parameters in order. The sandbox takes them by keyword only, so a
# positional call fails there; normalize() gives each positional argument its
# keyword, which is the only meaning such a call can have.
CALL_BOTO3_PARAMS = ("service_name", "operation_name", "region_name", "params")


def normalize(code):
    """(code, notes): call_boto3 calls rewritten from positional to keyword arguments.

    Only `name=` is inserted before each positional argument, so the rest of
    the script, comments and layout included, stays as written. A rewrite that
    does not parse, or that a call cannot take, leaves the code unchanged.
    """
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return code, []
    src = code.encode()
    starts = [0]
    for line in src.splitlines(keepends=True):
        starts.append(starts[-1] + len(line))
    inserts = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == "call_boto3" and node.args):
            continue
        if len(node.args) > len(CALL_BOTO3_PARAMS) or any(isinstance(a, ast.Starred) for a in node.args):
            continue
        names = CALL_BOTO3_PARAMS[:len(node.args)]
        if any(k.arg in names or k.arg is None for k in node.keywords):
            continue
        for name, arg in zip(names, node.args):
            inserts.append((starts[arg.lineno - 1] + arg.col_offset, f"{name}=".encode()))
    if not inserts:
        return code, []
    out = src
    for pos, text in sorted(inserts, reverse=True):
        out = out[:pos] + text + out[pos:]
    new = out.decode()
    try:
        ast.parse(new)
    except SyntaxError:
        return code, []
    return new, [f"gave {len(inserts)} positional call_boto3 argument(s) their keyword"]


PREVIEW_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "claude", "run-script")


def save_for_preview(code):
    """Keep the script where tuios's run-script-preview key finds it, one file per pane."""
    pane = os.environ.get("TUIOS_PANE_ID") or "no-pane"
    try:
        os.makedirs(PREVIEW_DIR, exist_ok=True)
        with open(os.path.join(PREVIEW_DIR, f"{pane}.py"), "w") as f:
            f.write(code + "\n")
    except OSError:
        pass


def main():
    if "--self-test" in sys.argv:
        return self_test()
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}
    notes = []
    if (tool_name[len(TOOL_PREFIX):] in SCRIPT_TOOLS and tool_name.startswith(TOOL_PREFIX)
            and isinstance(tool_input.get("code"), str)):
        code, notes = normalize(tool_input["code"])
        if notes:
            tool_input = {**tool_input, "code": code}
    try:
        decision, why = decide_tool(tool_name, tool_input)
    except Exception as e:  # a broken guard asks rather than waves through
        decision, why = "ask", f"aws-mcp-guard failed ({type(e).__name__}: {e})"
    if decision == "ask" and isinstance(tool_input.get("code"), str):
        save_for_preview(tool_input["code"])
    out = {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": why + (f" (normalized: {'; '.join(notes)})" if notes else ""),
    }
    if notes:
        out["updatedInput"] = tool_input
    print(json.dumps({"hookSpecificOutput": out}))
    return 0


CONFIG = """
[profile dev-readonly]
credential_process=aws-scoped-credentials --profile dev-developer --policy readonly --description x
[profile dev-agent]
credential_process=aws-scoped-credentials --profile dev-developer --policy agent
[profile dev-mixed]
credential_process=/Users/x/.local/bin/aws-scoped-credentials --profile dev-developer --policy readonly --policy agent
[profile dev-twice]
credential_process=aws-scoped-credentials --profile dev-developer --policy readonly --policy readonly
[profile fake-readonly]
credential_process=aws-vault export --format=json dev-developer
[profile path-readonly]
credential_process=aws-scoped-credentials --profile dev-developer --policy /tmp/readonly.json
[profile developer]
source_profile=capra-auth
[profile nono-readonly]
aws_access_key_id = NONOPLACEHOLDER0000000000000000
aws_secret_access_key = nono-placeholder
nono_scope = readonly
[profile nono-other]
aws_access_key_id = NONOPLACEHOLDER0000000000000001
nono_scope = agent
"""

NORMALIZE = [
    ('r = await call_boto3("rds", "DescribeDBInstances")',
     'call_boto3(service_name="rds", operation_name="DescribeDBInstances")'),
    ('r = await call_boto3("rds", "describe_events", "eu-west-1", {"Duration": 60})  # keep me',
     'region_name="eu-west-1", params={"Duration": 60})  # keep me'),
    ('await call_boto3("ec2", operation_name="DescribeVpcs")', 'service_name="ec2", operation_name='),
    ('await call_boto3("ec2", service_name="s3")', 'call_boto3("ec2", service_name="s3")'),
    ('await call_boto3(*args)', 'call_boto3(*args)'),
]


def self_test():
    failures = 0
    with tempfile.TemporaryDirectory() as d:
        cfg = os.path.join(d, "config")
        with open(cfg, "w") as f:
            f.write(CONFIG)
        cj = os.path.join(d, "claude.json")
        with open(cj, "w") as f:
            json.dump({"mcpServers": {"aws": {"env": {"AWS_MCP_PROXY_PROFILES": "dev-readonly dev-agent"}}}}, f)
        if proxy_profiles(cj) != ["dev-readonly", "dev-agent"]:
            failures += 1
            print(f"FAIL proxy_profiles: {proxy_profiles(cj)}")
        if proxy_profiles(os.path.join(d, "missing.json")) != []:
            failures += 1
            print("FAIL proxy_profiles on a missing file")
        rs = TOOL_PREFIX + "run_script"
        cases = [
            (TOOL_PREFIX + "search_documentation", {}, ["dev-readonly"], "allow"),
            (TOOL_PREFIX + "get_tasks", {"aws_profile": "dev-agent"}, ["dev-readonly"], "allow"),
            (TOOL_PREFIX + "get_presigned_url", {}, ["dev-readonly"], "ask"),
            (TOOL_PREFIX + "call_aws", {}, ["dev-readonly"], "ask"),
            (rs, {"code": "x"}, ["dev-readonly", "dev-agent"], "allow"),
            (TOOL_PREFIX + "run_script_readonly", {"code": "x"}, ["dev-readonly"], "allow"),
            (rs, {"code": "x", "aws_profile": "dev-readonly"}, ["dev-agent"], "allow"),
            (rs, {"code": "x", "aws_profile": "dev-twice"}, [], "allow"),
            (rs, {"code": "x", "aws_profile": "dev-agent"}, ["dev-readonly"], "ask"),
            (rs, {"code": "x"}, ["dev-agent", "dev-readonly"], "ask"),
            (rs, {"code": "x", "aws_profile": "dev-mixed"}, [], "ask"),
            (rs, {"code": "x", "aws_profile": "fake-readonly"}, [], "ask"),
            (rs, {"code": "x", "aws_profile": "path-readonly"}, [], "ask"),
            (rs, {"code": "x", "aws_profile": "developer"}, [], "ask"),
            (rs, {"code": "x", "aws_profile": "nono-readonly"}, [], "allow"),
            (rs, {"code": "x"}, ["nono-readonly"], "allow"),
            (rs, {"code": "x", "aws_profile": "nono-other"}, [], "ask"),
            (rs, {"code": "x", "aws_profile": "nope"}, [], "ask"),
            (rs, {"code": "x", "aws_profile": ["dev-readonly"]}, [], "ask"),
            (rs, {"code": "x"}, [], "ask"),
        ]
        for tool, tool_input, profiles, want in cases:
            got, why = decide_tool(tool, tool_input, profiles, cfg)
            if got != want:
                failures += 1
                print(f"FAIL {tool} {tool_input} {profiles}: got {got} ({why}), want {want}")
    for code, text in NORMALIZE:
        new, _ = normalize(code)
        if text not in new:
            failures += 1
            print(f"FAIL normalize {code!r}: {new!r}")
    print(f"{len(cases)} tool cases, {len(NORMALIZE)} normalize cases: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
