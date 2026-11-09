#!/usr/bin/env python3
"""PreToolUse hook for the AWS MCP server's tools (matcher `^mcp__aws__`). It
stands in for ask rules, which would override its allow: `run_script` is
allowed when the script only reads control-plane metadata, the documentation,
region and task-polling tools are allowed, and everything else asks,
`get_presigned_url` and any tool added to the server later included.

The sandbox reaches AWS only through
`call_boto3(service_name=..., operation_name=...)` and the `aws_mcp` helper
module. The script is parsed with `ast`, CPython's own parser, so the hook
reads the code the way the sandbox runs it. Each call_boto3 call is resolved
to the (service, operation) pairs it can make, following string literals,
names assigned from them, loops over literal tuples and lists, and the
parameters of local wrapper functions back to every place the wrapper is
called. Names are resolved without regard to statement order: every value a
name is ever given counts, which can only add pairs, never hide one.

It asks when a script:
- calls an operation without a read verb (a mutation),
- reads content: log events, S3 objects, SSM parameter values, DynamoDB
  items, secret values, RDS log files, stream records, query results,
- reads configuration that carries secrets: Lambda and ECS environment
  variables, EC2 user data, minted credentials,
- calls an aws_mcp helper, whose own AWS calls are not visible,
- makes a call it cannot resolve, or could reach call_boto3 other than by
  calling it by name (reflection, frames, an alias, an unusual import).

It guards against an agent reading or changing more than the user meant, not
against a script written to slip past it. A parse error or a crash asks.
When it asks, it saves the script to ~/.cache/claude/run-script/<pane>.py,
which prefix+p in tuios opens read-only in nvim in a popup.

`python3 run-script-guard.py --self-test` checks the cases at the bottom.
"""

import ast
import itertools
import json
import os
import re
import sys

READ_VERBS = (
    "describe", "list", "get", "batchget", "head", "lookup", "search",
    "validate", "estimate", "simulate",
)

# Read-only operations whose names do not start with a read verb.
READ_ALSO = {
    "cloudwatch": ["QueryMetrics"],
    "events": ["TestEventPattern"],
}

CONTENT = {
    "logs": [
        "GetLogEvents", "FilterLogEvents", "GetLogRecord", "GetLogObject",
        "StartQuery", "GetQueryResults", "StartLiveTail",
    ],
    "s3": ["GetObject", "GetObjectTorrent", "SelectObjectContent"],
    "ssm": [
        "GetParameter", "GetParameters", "GetParametersByPath",
        "GetParameterHistory", "GetCommandInvocation",
    ],
    "dynamodb": [
        "GetItem", "BatchGetItem", "Query", "Scan", "TransactGetItems",
        "ExecuteStatement", "BatchExecuteStatement", "ExecuteTransaction",
    ],
    "dynamodbstreams": ["GetRecords"],
    "kinesis": ["GetRecords"],
    "athena": ["GetQueryResults"],
    "rds": ["DownloadDBLogFilePortion"],
    "secretsmanager": ["GetSecretValue", "BatchGetSecretValue"],
}

# Configuration reads that return secrets: environment variables, user data,
# passwords and short-lived credentials.
SECRETS = {
    "lambda": ["GetFunction", "GetFunctionConfiguration"],
    "ecs": ["DescribeTaskDefinition"],
    "ec2": ["DescribeInstanceAttribute", "DescribeLaunchTemplateVersions", "GetPasswordData"],
    "sts": ["GetSessionToken", "GetFederationToken"],
    "ecr": ["GetAuthorizationToken"],
    "codeartifact": ["GetAuthorizationToken"],
    "sso": ["GetRoleCredentials"],
    "cognito-identity": ["GetCredentialsForIdentity"],
}

# Modules the sandbox pre-imports, its own helper module, and data-only
# modules for decoding payloads. Nothing here can reach the script's globals.
IMPORTABLE = {
    "asyncio", "collections", "csv", "dataclasses", "datetime", "decimal",
    "enum", "fractions", "functools", "itertools", "json", "math", "re",
    "statistics", "string", "time", "typing", "uuid", "io", "aws_mcp",
    "base64", "binascii", "gzip", "zlib", "hashlib", "textwrap", "urllib.parse",
}


def importable(module):
    return module in IMPORTABLE or module.split(".")[0] in IMPORTABLE
REFLECTION = {
    "eval", "exec", "compile", "__import__", "getattr", "setattr", "delattr",
    "globals", "locals", "vars", "breakpoint", "__builtins__", "__loader__", "__spec__",
}
FRAME_ATTRS = {
    "f_globals", "f_locals", "f_builtins", "f_back", "f_code",
    "gi_frame", "cr_frame", "ag_frame", "tb_frame", "tb_next",
}
DUNDERS_OK = {"__name__", "__qualname__", "__doc__", "__module__"}
AWS_MCP_OK = {"search_functions"}
MAX_VALUES = 256

FUNCTIONS = (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)
COMPREHENSIONS = (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)
LOOPS = (ast.For, ast.AsyncFor, ast.comprehension)
MATCH_BINDERS = tuple(getattr(ast, n) for n in ("MatchAs", "MatchStar", "MatchMapping") if hasattr(ast, n))


def op_key(operation):
    """The sandbox accepts snake_case as well as PascalCase operation names."""
    return re.sub(r"[^a-z0-9]", "", operation.lower())


def table(spec):
    return {(service, op_key(op)) for service, ops in spec.items() for op in ops}


CONTENT_OPS, SECRET_OPS, READ_ALSO_OPS = table(CONTENT), table(SECRETS), table(READ_ALSO)


def judge(service, operation):
    """None for a control-plane read, else why the call asks."""
    pair = (service.strip().lower(), op_key(operation))
    name = f"{service}:{operation}"
    if pair in CONTENT_OPS:
        return f"reads content ({name})"
    if pair in SECRET_OPS:
        return f"reads secrets ({name})"
    if pair in READ_ALSO_OPS or pair[1].startswith(READ_VERBS):
        return None
    return f"mutation ({name})"


class Unresolved(Exception):
    pass


class Script:
    def __init__(self, code):
        self.tree = ast.parse(code)
        self.parent = {}
        for node in ast.walk(self.tree):
            for child in ast.iter_child_nodes(node):
                self.parent[child] = node
        self.bindings = {}   # scope -> name -> binding nodes
        self.everywhere = {}  # name -> binding nodes in every scope
        self.declared = set()
        self.active = set()
        self._collect()

    def scope_of(self, node):
        """The function, comprehension or module whose names `node` sees."""
        grand, child, cur = None, node, self.parent.get(node)
        while cur is not None:
            if isinstance(cur, FUNCTIONS):
                body = cur.body if isinstance(cur.body, list) else [cur.body]
                if any(child is b for b in body):
                    return cur
            elif isinstance(cur, COMPREHENSIONS):
                # The first iterable is evaluated in the enclosing scope.
                first = cur.generators[0]
                if not (child is first and grand is first.iter):
                    return cur
            elif isinstance(cur, ast.Module):
                return cur
            grand, child, cur = child, cur, self.parent.get(cur)
        return self.tree

    def _bind(self, scope, name, node):
        self.bindings.setdefault(scope, {}).setdefault(name, []).append(node)
        self.everywhere.setdefault(name, []).append(node)

    def _collect(self):
        for node in ast.walk(self.tree):
            if isinstance(node, ast.Name) and not isinstance(node.ctx, ast.Load):
                scope = self.scope_of(node)
                if isinstance(self.parent.get(node), ast.NamedExpr):
                    while isinstance(scope, COMPREHENSIONS):
                        scope = self.scope_of(scope)
                self._bind(scope, node.id, node)
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                self._bind(self.scope_of(node), node.name, node)
            elif isinstance(node, ast.alias):
                self._bind(self.scope_of(node), node.asname or node.name.split(".")[0], node)
            elif isinstance(node, ast.ExceptHandler) and node.name:
                self._bind(self.scope_of(node), node.name, node)
            elif MATCH_BINDERS and isinstance(node, MATCH_BINDERS):
                name = getattr(node, "name", None) or getattr(node, "rest", None)
                if name:
                    self._bind(self.scope_of(node), name, node)
            elif isinstance(node, (ast.Global, ast.Nonlocal)):
                self.declared.update(node.names)
            if isinstance(node, FUNCTIONS):
                a = node.args
                for arg in a.posonlyargs + a.args + a.kwonlyargs + [a.vararg, a.kwarg]:
                    if arg:
                        self._bind(node, arg.arg, arg)

    def lookup(self, name, scope):
        if name in self.declared:
            raise Unresolved(f"`{name}` is declared global or nonlocal")
        while scope is not None:
            found = self.bindings.get(scope, {}).get(name)
            if found:
                return scope, found
            scope = None if isinstance(scope, ast.Module) else self.scope_of(scope)
        raise Unresolved(f"`{name}` is never assigned in the script")

    def values(self, expr, scope):
        """Every string `expr` can evaluate to, or Unresolved."""
        if isinstance(expr, ast.Constant) and isinstance(expr.value, str):
            return {expr.value}
        if isinstance(expr, ast.Name):
            return self.name_values(expr.id, scope)
        if isinstance(expr, ast.IfExp):
            return self.values(expr.body, scope) | self.values(expr.orelse, scope)
        if isinstance(expr, ast.JoinedStr):
            parts = []
            for v in expr.values:
                if isinstance(v, ast.FormattedValue):
                    if v.conversion not in (-1, ord("s")) or v.format_spec:
                        raise Unresolved(f"`{ast.unparse(expr)}` is formatted at run time")
                    v = v.value
                parts.append(self.values(v, scope))
            return self.join(parts)
        if isinstance(expr, ast.BinOp) and isinstance(expr.op, ast.Add):
            return self.join([self.values(expr.left, scope), self.values(expr.right, scope)])
        raise Unresolved(f"`{ast.unparse(expr)}` is computed at run time")

    @staticmethod
    def join(parts):
        size = 1
        for p in parts:
            size *= len(p)
        if size > MAX_VALUES:
            raise Unresolved("too many combinations to check")
        return {"".join(c) for c in itertools.product(*parts)}

    def name_values(self, name, scope):
        scope, found = self.lookup(name, scope)
        key = (name, id(scope))
        if key in self.active:
            raise Unresolved(f"`{name}` depends on itself")
        self.active.add(key)
        try:
            out = set()
            for binding in found:
                out |= self.binding_values(binding, name)
            if len(out) > MAX_VALUES:
                raise Unresolved(f"`{name}` takes too many values to check")
            return out
        finally:
            self.active.discard(key)

    def binding_values(self, b, name):
        if isinstance(b, ast.arg):
            return self.param_values(self.parent[self.parent[b]], b.arg)
        if not isinstance(b, ast.Name):
            raise Unresolved(f"`{name}` is bound to something other than a string")
        p = self.parent[b]
        if isinstance(p, ast.Assign) and any(t is b for t in p.targets):
            return self.values(p.value, self.scope_of(p))
        if isinstance(p, ast.AnnAssign) and p.target is b:
            return self.values(p.value, self.scope_of(p)) if p.value else set()
        path, cur = [], b
        while isinstance(self.parent[cur], (ast.Tuple, ast.List)):
            up = self.parent[cur]
            path.insert(0, next(i for i, e in enumerate(up.elts) if e is cur))
            cur = up
        loop = self.parent[cur]
        if not (isinstance(loop, LOOPS) and loop.target is cur):
            raise Unresolved(f"`{name}` is assigned in a way the guard cannot follow")
        out = set()
        for elt, scope in self.elements(loop.iter, self.scope_of(loop.iter)):
            for i in path:
                if (not isinstance(elt, (ast.Tuple, ast.List)) or i >= len(elt.elts)
                        or any(isinstance(e, ast.Starred) for e in elt.elts)):
                    raise Unresolved(f"cannot unpack `{ast.unparse(elt)}` into `{name}`")
                elt = elt.elts[i]
            out |= self.values(elt, scope)
        return out

    def elements(self, expr, scope):
        """The element expressions of a literal sequence a loop runs over."""
        if isinstance(expr, (ast.Tuple, ast.List, ast.Set)):
            if any(isinstance(e, ast.Starred) for e in expr.elts):
                raise Unresolved(f"`{ast.unparse(expr)}` unpacks another sequence")
            return [(e, scope) for e in expr.elts]
        if isinstance(expr, ast.Name):
            _, found = self.lookup(expr.id, scope)
            if len(found) == 1 and isinstance(found[0], ast.Name):
                p = self.parent[found[0]]
                if (isinstance(p, ast.Assign) and len(p.targets) == 1
                        and isinstance(p.value, (ast.Tuple, ast.List, ast.Set))
                        and self.only_iterated(expr.id)):
                    return self.elements(p.value, self.scope_of(p))
        raise Unresolved(f"cannot list what `{ast.unparse(expr)}` iterates over")

    def only_iterated(self, name):
        """True when `name` is read nowhere except as a loop's iterable, so it is never mutated."""
        for node in ast.walk(self.tree):
            if isinstance(node, ast.Name) and node.id == name and isinstance(node.ctx, ast.Load):
                p = self.parent.get(node)
                if not (isinstance(p, LOOPS) and p.iter is node):
                    return False
        return True

    def param_values(self, func, pname):
        """Every string passed for parameter `pname` at the calls of `func`."""
        if isinstance(func, ast.Lambda):
            raise Unresolved(f"`{pname}` is a lambda parameter")
        fname = func.name
        if func.decorator_list:
            raise Unresolved(f"`{fname}` is decorated")
        if isinstance(self.parent.get(func), ast.ClassDef):
            raise Unresolved(f"`{fname}` is a method")
        if len(self.everywhere.get(fname, [])) != 1:
            raise Unresolved(f"the name `{fname}` is bound more than once")
        a = func.args
        if pname in {x.arg for x in (a.vararg, a.kwarg) if x}:
            raise Unresolved(f"`{pname}` collects *args or **kwargs")
        calls = []
        for node in ast.walk(self.tree):
            if isinstance(node, ast.Name) and node.id == fname and isinstance(node.ctx, ast.Load):
                p = self.parent.get(node)
                if not (isinstance(p, ast.Call) and p.func is node):
                    raise Unresolved(f"`{fname}` is used other than by calling it")
                calls.append(p)
        positional = [x.arg for x in a.posonlyargs + a.args]
        posonly = {x.arg for x in a.posonlyargs}
        kwonly = [x.arg for x in a.kwonlyargs]
        out = set()
        for call in calls:
            if any(isinstance(x, ast.Starred) for x in call.args) or any(k.arg is None for k in call.keywords):
                raise Unresolved(f"a call to `{fname}` unpacks its arguments")
            given = {k.arg: k.value for k in call.keywords}
            expr, scope = None, self.scope_of(call)
            if pname in positional:
                i = positional.index(pname)
                first_default = len(positional) - len(a.defaults)
                if i < len(call.args):
                    expr = call.args[i]
                elif pname in given and pname not in posonly:
                    expr = given[pname]
                elif i >= first_default:
                    expr, scope = a.defaults[i - first_default], self.scope_of(func)
            else:
                j = kwonly.index(pname)
                if pname in given:
                    expr = given[pname]
                elif a.kw_defaults[j] is not None:
                    expr, scope = a.kw_defaults[j], self.scope_of(func)
            if expr is not None:  # a missing argument is a TypeError: the body never runs
                out |= self.values(expr, scope)
        return out

    def escapes(self):
        """Ways the script could reach AWS other than a call_boto3 call it can read."""
        out = []
        for node in ast.walk(self.tree):
            p = self.parent.get(node)
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
                if node.id in REFLECTION:
                    out.append(f"uses {node.id}")
                elif node.id == "call_boto3" and not (isinstance(p, ast.Call) and p.func is node):
                    out.append("uses call_boto3 other than by calling it")
                elif node.id == "aws_mcp":
                    if isinstance(p, ast.Attribute) and p.value is node:
                        if p.attr not in AWS_MCP_OK:
                            out.append(f"calls aws_mcp.{p.attr}, whose AWS calls are not visible")
                    elif not (isinstance(p, ast.Call) and isinstance(p.func, ast.Name)
                              and p.func.id in ("help", "dir") and len(p.args) == 1
                              and p.args[0] is node and not p.keywords):
                        out.append("uses aws_mcp as a value")
            elif isinstance(node, ast.Attribute):
                a = node.attr
                if a in FRAME_ATTRS or (a.startswith("__") and a.endswith("__") and a not in DUNDERS_OK):
                    out.append(f"uses .{a}")
            elif isinstance(node, ast.Constant) and isinstance(node.value, str):
                if "call_boto3" in node.value or "aws_mcp" in node.value:
                    out.append("names call_boto3 or aws_mcp in a string")
            elif isinstance(node, ast.Import):
                for al in node.names:
                    if not importable(al.name):
                        out.append(f"imports {al.name}")
                    elif al.name.split(".")[0] == "aws_mcp" and (al.asname or al.name != "aws_mcp"):
                        out.append(f"imports {al.name} as {al.asname}")
            elif isinstance(node, ast.ImportFrom):
                module = node.module or ""
                if node.level or not importable(module):
                    out.append(f"imports from {'.' * node.level}{module}")
                elif module.split(".")[0] == "aws_mcp":
                    out.append("imports from aws_mcp")
        if self.everywhere.get("call_boto3"):
            out.append("redefines call_boto3")
        if any(not (isinstance(b, ast.alias) and b.name == "aws_mcp" and not b.asname)
               for b in self.everywhere.get("aws_mcp", [])):
            out.append("rebinds aws_mcp")
        return out


def dedupe(items):
    return list(dict.fromkeys(items))


def evaluate(code):
    """(reasons to ask, (service, operation) pairs the script can call)."""
    s = Script(code)
    reasons, pairs = s.escapes(), []
    calls = [n for n in ast.walk(s.tree) if isinstance(n, ast.Call)
             and isinstance(n.func, ast.Name) and n.func.id == "call_boto3"]
    for node in sorted(calls, key=lambda n: (n.lineno, n.col_offset)):
        where = f"call_boto3 on line {node.lineno}"
        given = {k.arg: k.value for k in node.keywords}
        if None in given:
            reasons.append(f"{where} unpacks **kwargs")
            continue
        if node.args or "service_name" not in given or "operation_name" not in given:
            reasons.append(f"{where} does not name service_name and operation_name")
            continue
        scope = s.scope_of(node)
        try:
            services = s.values(given["service_name"], scope)
            operations = s.values(given["operation_name"], scope)
        except Unresolved as e:
            reasons.append(f"{where}: {e}")
            continue
        for pair in itertools.product(sorted(services), sorted(operations)):
            pairs.append(pair)
            why = judge(*pair)
            if why:
                reasons.append(why)
    return dedupe(reasons), dedupe(pairs)


def decide(code):
    try:
        reasons, pairs = evaluate(code)
    except SyntaxError as e:
        reasons, pairs = [f"the script does not parse ({e.msg}, line {e.lineno})"], []
    except Exception as e:  # a broken guard asks rather than waves through
        reasons, pairs = [f"run-script-guard failed ({type(e).__name__}: {e})"], []
    if reasons:
        shown = reasons[:10] + ([f"and {len(reasons) - 10} more"] if len(reasons) > 10 else [])
        return "ask", "run_script: " + "; ".join(shown)
    calls = ", ".join(f"{s}:{o}" for s, o in pairs) or "no AWS calls"
    return "allow", f"run_script only reads control-plane metadata: {calls}"


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


TOOL_PREFIX = "mcp__aws__aws___"
SCRIPT_TOOLS = {"run_script", "run_script_readonly"}
# Documentation, skills, region data, and polling of a script already decided on.
SAFE_TOOLS = {
    "search_documentation", "read_documentation", "retrieve_skill",
    "list_regions", "get_regional_availability", "get_tasks",
}


def decide_tool(tool_name, tool_input):
    """Decision for any tool on the aws MCP server; tools it does not know ask."""
    name = tool_name[len(TOOL_PREFIX):] if tool_name.startswith(TOOL_PREFIX) else tool_name
    if name in SCRIPT_TOOLS:
        code = tool_input.get("code")
        if not isinstance(code, str):
            return "ask", f"{name} without a code string"
        return decide(code)
    if name == "get_presigned_url":
        return "ask", "get_presigned_url hands out read or write access to an S3 object"
    if name in SAFE_TOOLS:
        return "allow", f"{name} reads no account data"
    return "ask", f"{tool_name} is not a tool run-script-guard knows"


def main():
    if "--self-test" in sys.argv:
        return self_test()
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    tool_input = data.get("tool_input") or {}
    decision, why = decide_tool(data.get("tool_name", ""), tool_input)
    if decision == "ask" and isinstance(tool_input.get("code"), str):
        save_for_preview(tool_input["code"])
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": why,
    }}))
    return 0


WRAPPER = """
async def cb(svc, op, params=None):
    return await call_boto3(service_name=svc, operation_name=op, region_name="eu-west-1", params=params or {})
"""

ALLOW = [
    'r = await call_boto3(service_name="ec2", operation_name="DescribeVpcs", region_name="eu-west-1")\nr',
    'R = "eu-west-1"\nS = "logs"\nawait call_boto3(service_name=S, operation_name="DescribeLogGroups", region_name=R)',
    WRAPPER + 'a = await cb("ec2", "DescribeVpcs")\nb = await cb("ecs", "ListClusters", {"x": 1})',
    'for op in ("ListResolverEndpoints", "ListResolverRules"):\n'
    '    await call_boto3(service_name="route53resolver", operation_name=op)',
    'CALLS = [("ec2", "DescribeVpcs"), ("rds", "DescribeDBInstances")]\n'
    'for s, o in CALLS:\n    await call_boto3(service_name=s, operation_name=o)',
    'rs = await asyncio.gather(*[call_boto3(service_name="ec2", operation_name="DescribeRegions", region_name=r)'
    ' for r in ["eu-west-1", "eu-north-1"]], return_exceptions=True)',
    'await call_boto3(service_name="cloudformation", operation_name="describe_stacks")',
    'await call_boto3(service_name="cloudwatch", operation_name="QueryMetrics", params={})',
    'await call_boto3(service_name="s3", operation_name="ListObjectsV2", params={"Bucket": "b"})',
    'import aws_mcp\nhelp(aws_mcp)\nawait aws_mcp.search_functions("idle resources")',
    'try:\n    await call_boto3(service_name="sts", operation_name="GetCallerIdentity")\n'
    'except ClientError as e:\n    result = type(e).__name__',
    'async def c(o, s="ec2"):\n    return await call_boto3(service_name=s, operation_name=o)\n'
    'await c("DescribeSubnets")\nawait c(o="ListBuckets", s="s3")',
    'async def unused(s, o):\n    return await call_boto3(service_name=s, operation_name=o)',
    'p = "Describe"\nawait call_boto3(service_name="ec2", operation_name=f"{p}Vpcs")',
    'import json, time as _t, base64, urllib.parse\nfrom datetime import datetime as D\nfrom urllib.parse import quote\n'
    'await call_boto3(service_name="ecs", operation_name="DescribeServices", params={})',
]

ASK = [
    ('await call_boto3(service_name="logs", operation_name="FilterLogEvents", params={})', "reads content (logs:FilterLogEvents)"),
    (WRAPPER + 'await cb("logs", "GetLogEvents")', "reads content (logs:GetLogEvents)"),
    ('await call_boto3(service_name="s3", operation_name="GetObject", params={})', "reads content (s3:GetObject)"),
    ('await call_boto3(service_name="ssm", operation_name="GetParametersByPath")', "reads content (ssm:GetParametersByPath)"),
    ('await call_boto3(service_name="dynamodb", operation_name="Scan")', "reads content (dynamodb:Scan)"),
    ('await call_boto3(service_name="secretsmanager", operation_name="get_secret_value")', "reads content"),
    ('await call_boto3(service_name="lambda", operation_name="GetFunctionConfiguration")', "reads secrets (lambda:GetFunctionConfiguration)"),
    ('await call_boto3(service_name="ecs", operation_name="DescribeTaskDefinition")', "reads secrets (ecs:DescribeTaskDefinition)"),
    ('await call_boto3(service_name="ec2", operation_name="DescribeInstanceAttribute")', "reads secrets"),
    ('await call_boto3(service_name="ec2", operation_name="TerminateInstances")', "mutation (ec2:TerminateInstances)"),
    ('await call_boto3(service_name="s3", operation_name="delete_bucket")', "mutation"),
    ('for op in ("DescribeLogGroups", "FilterLogEvents"):\n    await call_boto3(service_name="logs", operation_name=op)',
     "reads content (logs:FilterLogEvents)"),
    ('op = "DescribeVpcs"\nop = "DeleteVpc"\nawait call_boto3(service_name="ec2", operation_name=op)', "mutation (ec2:DeleteVpc)"),
    ('op = "FilterLogEvents"\nxs = [op for op in ("DescribeLogGroups",)]\nawait call_boto3(service_name="logs", operation_name=op)',
     "reads content (logs:FilterLogEvents)"),
    ('for g in groups:\n    await call_boto3(service_name="logs", operation_name=g["op"])', "computed at run time"),
    ('async def safe(**kw):\n    return await call_boto3(service_name="ec2", **kw)\nawait safe(operation_name="DescribeVpcs")',
     "unpacks **kwargs"),
    (WRAPPER + 'fs = [cb]', "used other than by calling it"),
    ('@retry\nasync def cb(s, o):\n    return await call_boto3(service_name=s, operation_name=o)\nawait cb("ec2", "DescribeVpcs")',
     "is decorated"),
    ('class C:\n    async def cb(self, s, o):\n        return await call_boto3(service_name=s, operation_name=o)', "is a method"),
    ('async def cb(s):\n    global S\n    return await call_boto3(service_name=S, operation_name="DescribeVpcs")', "global"),
    ('f = getattr(x, "y")', "uses getattr"),
    ('f = call_boto3\nawait f(service_name="ec2", operation_name="DescribeVpcs")', "other than by calling it"),
    ('import aws_mcp as m\nawait m.search_functions("x")', "imports aws_mcp as m"),
    ('aws_mcp = 1', "rebinds aws_mcp"),
    ('import aws_mcp\nawait aws_mcp.find_idle_resources()', "aws_mcp.find_idle_resources"),
    ('globals()["call_boto3"](service_name="ec2", operation_name="DeleteVpc")', "uses globals"),
    ('import sys', "imports sys"),
    ('import urllib.request', "imports urllib.request"),
    ('x = ().__class__.__base__', "uses .__class__"),
    ('if (op := "DeleteVpc"):\n    await call_boto3(service_name="ec2", operation_name=op)', "cannot follow"),
    ('async def cb(s, o):\n    return await call_boto3(service_name=s, operation_name=o)\nawait cb(*args)', "unpacks its arguments"),
    ('await call_boto3(service_name="ec2", operation_name=', "does not parse"),
]


def self_test():
    failures = 0
    for code in ALLOW:
        decision, why = decide(code)
        if decision != "allow":
            failures += 1
            print(f"FAIL should allow: {code!r}\n  {why}")
    for code, want in ASK:
        decision, why = decide(code)
        if decision != "ask" or want not in why:
            failures += 1
            print(f"FAIL should ask with {want!r}: {code!r}\n  got {decision}: {why}")
    tools = [
        ("mcp__aws__aws___search_documentation", {}, "allow"),
        ("mcp__aws__aws___get_tasks", {}, "allow"),
        ("mcp__aws__aws___get_presigned_url", {}, "ask"),
        ("mcp__aws__aws___call_aws", {}, "ask"),
        ("mcp__aws__aws___run_script", {}, "ask"),
        ("mcp__aws__aws___run_script_readonly", {"code": ALLOW[0]}, "allow"),
        ("mcp__aws__aws___run_script", {"code": ASK[0][0]}, "ask"),
    ]
    for tool, tool_input, want in tools:
        got, why = decide_tool(tool, tool_input)
        if got != want:
            failures += 1
            print(f"FAIL {tool} {tool_input}: got {got} ({why}), want {want}")
    print(f"{len(ALLOW)} allow, {len(ASK)} ask, {len(tools)} tool cases: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
