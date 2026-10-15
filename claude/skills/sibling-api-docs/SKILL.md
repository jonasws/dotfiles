---
name: sibling-api-docs
description: >-
  Read another Vy/CargoNet service's API contract (its OpenAPI spec rendered to
  markdown) instead of its source code. Use whenever work in one repo under ~/CX,
  ~/CNOPS or ~/CN-TERMINAL depends on a different service there: calling its
  endpoints, mapping its request/response DTOs, writing a client, mock or contract
  test against it, or answering "what does the journey / booking / consignment /
  terminal service expose, accept or return". Applies when the user names the
  service rather than a path, and before grepping a sibling repo's controllers or
  DTOs. Treat the other service as a black box; open its source only when asked to.
---

# Sibling API docs

When the task lives in one service and touches another, work from the other
service's **published contract**, the way a black-box test would. Its source shows
how it behaves today, including internals nobody promised to keep. Its OpenAPI spec
shows what it promises. Code written against the promise survives the other team's
refactors; code written against the source breaks on them.

Reading the source is therefore off by default. Go there only when:

- the user asks you to dig into that service's implementation, or
- the contract cannot answer the question (undocumented error behavior, a field
  whose meaning the spec leaves open). Then **say the docs don't cover it and ask**
  before opening the source, and mark any answer taken from source as such.

The repo you are working in is not a sibling: read its own source as usual.

## Render the docs

```bash
~/.claude/skills/sibling-api-docs/render-api-docs.sh ~/CNOPS/cn-cnops-journey
```

It prints the output directory, the spec's path in the repo, the raw copy it
rendered (`raw:`), and the git ref. Cite the ref.

- Finds the spec with `fd`. Specs pinned by the snapshot test
  (`**/src/test/resources/__snapshots__/openapi-schema.json`) win over hand-kept
  `openapi.json`/`swagger.yaml`. With several matches it lists them: pass a spec path
  instead of the repo to pick one.
- Renders the spec **as on `origin/HEAD`**, after a fetch, so a feature branch or
  uncommitted edits in the clone do not leak in. Add `--working-tree` only when the
  question is about the checked-out branch, and say which branch.
- Writes to `<root>/api-docs/<repo>/`. The workspace roots are not git repos, so
  nothing lands in a commit.
- Re-render every time before reading: it takes under a second, so there is no
  staleness to reason about.
- A path that is not a clone fails with "neither a spec file nor inside a git
  clone". Say the service is not cloned; do not guess its API.

No spec found means the service has no HTTP contract in the repo (a webapp, a
consumer, an event-only service). Say so. Events on EventBridge/SNS/SQS are not in
OpenAPI. Look for a published schema or event library first, and ask before reading
the producer's code.

## Read the docs

The output is built for agents. Read in this order:

1. `AGENTS.md`: artifact map and the service description.
2. `llms.txt`: compact index of tags, operations and model groups. Small enough to read whole.
3. `operations/<slug>.md`: one endpoint with parameters, security, request/response and a curl example.
4. `models/schemas/<slug>.md`: one DTO, linked from the operation pages.

`llms-full.txt` and the `llms-*-NNNN.txt` shards run to hundreds of KB. Grep them
(`rg -n 'trainNumber' llms-full.txt`), never read them whole.

The render skips HTML and JSON artifacts, so the `bundle.json`, `operations/*.json`
and `index.html` entries in `AGENTS.md` do not exist. Their machine-readable stand-in
is the raw spec the script prints as `raw:`. It is still the contract, not source.
Query it with `jq` for what the markdown flattens away:

- **Nullability.** A field can be listed as required and still be nullable, which
  shows up only as `anyOf: [..., {"type": "null"}]`. Check before generating DTOs:
  `jq '.components.schemas.JourneyDto.properties.canceledOrigin' <raw>`
- **Hosts.** The markdown's base URL is `localhost`; the real environments are in
  `jq .servers <raw>`.

A tag such as `Internal` has no meaning the spec defines. Mention it when the
operation you recommend carries one, rather than deciding for the user whether a
sibling may call it.

The `journey` and `ruteplan` MCP servers return live data, not the contract. Use
them to look at a real response, never to settle what a field promises.

## Reporting

Name the docs directory, the operation or model page, and the ref the script
printed, for example `cn-cnops-journey @ origin/HEAD 538a7e74: operations/<slug>.md`.
If any part of the answer came from the service's source, say which part and why
the contract was not enough.
