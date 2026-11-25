#!/usr/bin/env python3
"""Generate the AWS half of the nono agent profile from aws/config.

Writes two committed files and one local one:

- nono/aws/config: the AWS config the sandbox sees (AWS_CONFIG_FILE). One
  profile per `-readonly` profile in aws/config, same name and region, with a
  placeholder access key and `nono_scope = readonly`. The placeholder keys are
  not credentials: nono's proxy reads the key ID from each request's signature
  and re-signs with the host profile it maps to.
- nono/profiles/liflig-aws.json: the `aws_auth` routes. One route per AWS
  service, region wildcard, each mapping every placeholder key to its host
  profile, with an endpoint policy that allows read operations only.
- ~/.local/share/nono-agent/aws-context.md, not tracked: what the agent can
  and cannot read, from the policy in aws/policies and the routes above.
  launch-agent's SessionStart hook hands it to sandboxed Claude sessions, which
  can read that folder (liflig-base.json).

Agents get read-only AWS: the host profiles are scoped by an IAM session policy,
and nono refuses any operation that is not a read before it is signed. Writes
are left to you, outside the sandbox.

Run after changing aws/config:  python3 -I nono/tools/gen-aws.py
"""

import configparser
import hashlib
import json
import pathlib
import shlex

ROOT = pathlib.Path(__file__).resolve().parents[2]
AWS_CONFIG = ROOT / "aws" / "config"
OUT_CONFIG = ROOT / "nono" / "aws" / "config"
OUT_PROFILE = ROOT / "nono" / "profiles" / "liflig-aws.json"
OUT_CONTEXT = pathlib.Path.home() / ".local" / "share" / "nono-agent" / "aws-context.md"
POLICY_DIR = ROOT / "aws" / "policies"
SCHEMA = "https://raw.githubusercontent.com/nolabs-ai/nono/refs/heads/main/crates/nono-cli/data/nono-profile.schema.json"

READ_OPERATIONS = ["Describe*", "List*", "Get*", "BatchGet*", "Search*", "Lookup*"]

# Services whose operation nono reads from the request (JSON, Query, RPCv2).
OPERATION_SERVICES = [
    "acm", "api.ecr", "application-autoscaling", "autoscaling", "cloudformation",
    "codebuild", "codepipeline", "cognito-idp", "dynamodb", "ec2", "ecs",
    "elasticloadbalancing", "events", "kms", "logs", "monitoring", "rds",
    "scheduler", "secretsmanager", "sns", "sqs", "ssm", "states", "tagging",
    "wafv2",
]
# REST services: no operation name to read, so only GET and HEAD pass.
REST_SERVICES = ["apigateway", "lambda", "s3"]
# Global endpoints, signed in us-east-1.
GLOBAL_QUERY_SERVICES = {"iam": "iam.amazonaws.com"}
GLOBAL_REST_SERVICES = {"route53": "route53.amazonaws.com", "cloudfront": "cloudfront.amazonaws.com"}


# SigV4 signing names that differ from the endpoint prefix.
SIGNING_NAMES = {"api.ecr": "ecr"}


# What each Deny pattern in the agents' policy withholds, in words an agent can
# act on. A Deny pattern missing here stops the run, so the agent context can
# never describe an older policy.
DENY_MEANING = {
    "dynamodb:*Item*": "DynamoDB items",
    "dynamodb:Query": "DynamoDB items",
    "dynamodb:Scan": "DynamoDB items",
    "dynamodb:*Statement": "DynamoDB items",
    "ec2:DescribeInstanceAttribute": "EC2 user data, launch template contents and console output",
    "ec2:DescribeLaunchTemplateVersions": "EC2 user data, launch template contents and console output",
    "ec2:GetPasswordData": "EC2 user data, launch template contents and console output",
    "ec2:GetConsoleOutput": "EC2 user data, launch template contents and console output",
    "ec2:GetConsoleScreenshot": "EC2 user data, launch template contents and console output",
    "ecr:GetAuthorizationToken": "ECR registry logins and image layers",
    "ecr:GetDownloadUrlForLayer": "ECR registry logins and image layers",
    "ecs:DescribeTaskDefinition": "ECS task definitions, which hold container environments",
    "lambda:GetFunction": "Lambda function code and configuration, which hold environments",
    "lambda:GetFunctionConfiguration": "Lambda function code and configuration, which hold environments",
    "logs:Get*": "CloudWatch log events and Logs Insights queries",
    "logs:FilterLogEvents": "CloudWatch log events and Logs Insights queries",
    "logs:StartQuery": "CloudWatch log events and Logs Insights queries",
    "logs:StartLiveTail": "CloudWatch log events and Logs Insights queries",
    "rds:DownloadDBLogFilePortion": "RDS log files",
    "s3:GetObject*": "S3 object contents",
    "sqs:ReceiveMessage": "SQS messages",
    "ssm:GetParameter*": "SSM parameter values and Run Command output",
    "ssm:GetCommandInvocation": "SSM parameter values and Run Command output",
}

# IAM service prefixes whose endpoint prefix differs.
IAM_PREFIXES = {"monitoring": "cloudwatch", "api.ecr": "ecr", "tagging": "tag"}
REST_IAM_PREFIXES = set(REST_SERVICES) | set(GLOBAL_REST_SERVICES)


def nono_forwards(action):
    """Whether nono's proxy forwards a request for this IAM action on the CLI path."""
    service, operation = action.split(":", 1)
    if service == "sts":
        return operation == "GetCallerIdentity"
    if service in REST_IAM_PREFIXES:
        return True
    routed = {IAM_PREFIXES.get(s, s) for s in OPERATION_SERVICES} | set(GLOBAL_QUERY_SERVICES)
    return service in routed and any(operation.startswith(p.rstrip("*")) for p in READ_OPERATIONS)


def scoped_profile(parser, name):
    """(host profile, policy names) from a -readonly profile's credential_process."""
    argv = shlex.split(parser.get(f"profile {name}", "credential_process", fallback=""))
    if not argv or pathlib.Path(argv[0]).name != "aws-scoped-credentials":
        raise SystemExit(f"profile {name} does not use aws-scoped-credentials")
    pairs = list(zip(argv, argv[1:]))
    parent = next((v for k, v in pairs if k == "--profile"), None)
    policies = tuple(v for k, v in pairs if k == "--policy")
    if not parent or not policies:
        raise SystemExit(f"profile {name} names no --profile or --policy")
    return parent, policies


def grouped(actions):
    """'svc: a, b; svc2: c' for a list of svc:Op actions, services in first-seen order."""
    by_service = {}
    for action in actions:
        service, operation = action.split(":", 1)
        by_service.setdefault(service, []).append(operation)
    return "; ".join(f"{s} {', '.join(ops)}" for s, ops in by_service.items())


def profile_summary(profiles, parents):
    """One paragraph naming the profiles, or a list when they break the naming rule."""
    split = {}
    for name in profiles:
        base = name.removesuffix("-readonly")
        account, _, env = base.rpartition("-")
        if not account or parents[name] != f"{base}-developer":
            split = None
            break
        split[name] = (account, env)
    regions = sorted(set(profiles.values()))
    region = f"region {regions[0]}" if len(regions) == 1 else "regions vary per profile"
    if split is None:
        listed = ", ".join(f"{n} (outside: {parents[n]}, {profiles[n]})" for n in sorted(profiles))
        return f"Profiles: {listed}."
    order = ["build", "dev", "staging", "prod"]
    accounts = sorted({a for a, _ in split.values()})
    envs = sorted({e for _, e in split.values()}, key=lambda e: (order.index(e) if e in order else len(order), e))
    full = len(split) == len(accounts) * len(envs)
    shape = (f"`<account>-<env>-readonly`, account {' | '.join(accounts)}, env {' | '.join(envs)}" if full
             else ", ".join(f"`{n}`" for n in sorted(profiles)))
    return (f"Profiles: {shape}; {region}. Outside the sandbox the user has the same name "
            "ending in `-developer`.")


def agent_context(profiles, parents, policy_name, policy):
    statements = policy["Statement"]
    allowed = [a for s in statements if s["Effect"] == "Allow" for a in s["Action"]]
    denied = [a for s in statements if s["Effect"] == "Deny" for a in s["Action"]]
    missing = [a for a in denied if a not in DENY_MEANING]
    if missing:
        raise SystemExit(f"add DENY_MEANING entries in {pathlib.Path(__file__).name} for: {', '.join(missing)}")
    withheld = {}
    for action in denied:
        withheld.setdefault(DENY_MEANING[action], []).append(action)
    cli_refused = [a for a in allowed if not nono_forwards(a)]
    example = "cnops-dev-readonly" if "cnops-dev-readonly" in profiles else sorted(profiles)[0]

    lines = [
        "# AWS in this sandbox",
        "",
        f"(Generated by nono/tools/gen-aws.py from aws/config and aws/policies/{policy_name}.json.)",
        "",
        "Read-only control-plane metadata: which resources exist, their configuration, status,",
        "tags and metrics. Content stored in or passing through them (see Denied) and every",
        "write are out of reach.",
        "",
        profile_summary(profiles, parents)
        + " No default, AWS_PROFILE unset: pass `--profile` every time. Account follows the repo"
        " folder (~/CNOPS cnops, ~/CX cn-cx, ~/CN-TERMINAL cn-terminal); with no environment in"
        " the prompt, use dev and say so.",
        "",
        "Allowed by the IAM session policy, all else denied: " + grouped(allowed) + ".",
        "",
        "Denied even where an allow pattern matches:",
    ]
    lines += [f"- {meaning}: {grouped(actions)}" for meaning, actions in withheld.items()]
    proxy = (
        "The CLI and SDKs also pass nono's proxy, which forwards only operations named "
        + "/".join(p.rstrip("*") for p in READ_OPERATIONS) + "*, GET/HEAD for "
        + ", ".join(sorted(REST_IAM_PREFIXES)) + ", and sts GetCallerIdentity; anything else gets HTTP 403."
    )
    if cli_refused:
        proxy += " Allowed by the policy but refused there: " + ", ".join(cli_refused) + "."
    proxy += " The AWS MCP server's run_script checks only the policy."
    lines += [
        "",
        proxy,
        "",
        "Need content? Don't try a denied call (AccessDenied, a wasted round trip). Answer from"
        " metadata, then give the user the command to run in another pane outside the sandbox,"
        f" for example `aws logs tail <log-group> --since 1h --profile {parents[example]}`.",
        "",
    ]
    return "\n".join(lines)

def placeholder_key(profile):
    digest = hashlib.sha256(profile.encode()).hexdigest().upper()
    return "NONOPLACEHOLDER" + "".join(c for c in digest if c.isalnum())[:16]


def operation_policy(operations):
    rules = [{"method": m, "path": "/**", "operations": operations} for m in ("POST", "GET")]
    return {"default": {"decision": "deny"}, "allow": rules}


def rest_policy():
    return {"default": {"decision": "deny"}, "allow": [{"method": m, "path": "/**"} for m in ("GET", "HEAD")]}


def main():
    parser = configparser.RawConfigParser(comment_prefixes=(";", "#"), strict=False)
    parser.read(AWS_CONFIG)
    profiles = {}
    parents = {}
    policy_sets = set()
    for section in parser.sections():
        if section.startswith("profile ") and section.endswith("-readonly"):
            name = section.removeprefix("profile ")
            profiles[name] = parser.get(section, "region", fallback="eu-west-1")
            parents[name], policies = scoped_profile(parser, name)
            policy_sets.add(policies)
    if not profiles:
        raise SystemExit(f"no -readonly profiles in {AWS_CONFIG}")
    if len(policy_sets) != 1 or len(next(iter(policy_sets))) != 1:
        raise SystemExit("the agent context describes one policy, but the -readonly profiles use "
                         + ", ".join("+".join(p) for p in sorted(policy_sets)))
    policy_name = next(iter(policy_sets))[0]
    if "/" in policy_name:
        raise SystemExit(f"the -readonly profiles name a policy by path ({policy_name}); name one in aws/policies")
    policy = json.loads((POLICY_DIR / f"{policy_name}.json").read_text())

    keys = {placeholder_key(name): name for name in sorted(profiles)}

    lines = [
        "; Generated by nono/tools/gen-aws.py from aws/config. Do not edit.",
        "; The AWS config agents see inside nono (AWS_CONFIG_FILE). The keys are",
        "; placeholders: nono's proxy maps each to the host profile of the same name",
        "; and re-signs the request, so no usable credential is in the sandbox.",
        "",
    ]
    for key, name in keys.items():
        lines += [
            f"[profile {name}]",
            f"region = {profiles[name]}",
            f"aws_access_key_id = {key}",
            "aws_secret_access_key = nono-placeholder",
            "nono_scope = readonly",
            "",
        ]
    OUT_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    OUT_CONFIG.write_text("\n".join(lines))

    aws_auth = {"profiles": keys}
    routes = {}
    for service in OPERATION_SERVICES:
        routes[f"aws_{service.replace('.', '_').replace('-', '_')}"] = {
            "upstream": f"https://{service}.*.amazonaws.com",
            "aws_auth": {**aws_auth, "service": SIGNING_NAMES.get(service, service)},
            "endpoint_policy": operation_policy(READ_OPERATIONS),
        }
    routes["aws_sts"] = {
        "upstream": "https://sts.*.amazonaws.com",
        "aws_auth": {**aws_auth, "service": "sts"},
        "endpoint_policy": operation_policy(["GetCallerIdentity"]),
    }
    for service in REST_SERVICES:
        routes[f"aws_{service}"] = {
            "upstream": f"https://{service}.*.amazonaws.com",
            "aws_auth": {**aws_auth, "service": service},
            "endpoint_policy": rest_policy(),
        }
    # The CLI and SDKs address a bucket virtual-hosted (bucket.s3.REGION...)
    # by default; s3.*.amazonaws.com only covers path-style requests.
    routes["aws_s3_bucket"] = {
        "upstream": "https://*.s3.*.amazonaws.com",
        "aws_auth": {**aws_auth, "service": "s3"},
        "endpoint_policy": rest_policy(),
    }
    for service, host in GLOBAL_QUERY_SERVICES.items():
        routes[f"aws_{service}"] = {
            "upstream": f"https://{host}",
            "aws_auth": {**aws_auth, "region": "us-east-1", "service": service},
            "endpoint_policy": operation_policy(READ_OPERATIONS),
        }
    for service, host in GLOBAL_REST_SERVICES.items():
        routes[f"aws_{service}"] = {
            "upstream": f"https://{host}",
            "aws_auth": {**aws_auth, "region": "us-east-1", "service": service},
            "endpoint_policy": rest_policy(),
        }
    # The hosted AWS MCP Server. Its run_script calls AWS server-side as the
    # identity that signed the request, so nono cannot filter those calls; the
    # host profiles' IAM session policy is what limits them.
    routes["aws_mcp"] = {
        "upstream": "https://aws-mcp.*.api.aws",
        "aws_auth": {**aws_auth, "service": "aws-mcp"},
    }

    profile = {
        "$schema": SCHEMA,
        "meta": {
            "name": "liflig-aws",
            "description": "Generated by nono/tools/gen-aws.py: read-only AWS through nono's SigV4 re-signing",
        },
        "network": {
            "credentials": sorted(routes),
            "custom_credentials": routes,
        },
        "environment": {
            "deny_vars": [
                "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
                "AWS_PROFILE", "AWS_DEFAULT_PROFILE", "AWS_VAULT*", "AWS_CONTAINER_*",
            ],
            "set_vars": {
                "AWS_CONFIG_FILE": "$HOME/.config/nono/aws/config",
                "AWS_SHARED_CREDENTIALS_FILE": "/dev/null",
                "AWS_REGION": "eu-west-1",
            },
        },
    }
    OUT_PROFILE.write_text(json.dumps(profile, indent=2) + "\n")
    OUT_CONTEXT.parent.mkdir(parents=True, exist_ok=True)
    OUT_CONTEXT.write_text(agent_context(profiles, parents, policy_name, policy))
    print(f"{len(keys)} profiles, {len(routes)} routes -> {OUT_CONFIG.relative_to(ROOT)}, "
          f"{OUT_PROFILE.relative_to(ROOT)}, {OUT_CONTEXT}")


if __name__ == "__main__":
    main()
