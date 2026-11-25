# Unverified probes

Checks for the agent sandbox and docs tooling that were written or changed
without being run where they matter: on the Mac, inside nono, against the real
services. Most were authored in a Linux container with no keychain, no Seatbelt,
no tuios and no API keys; some were tested there against stubs, as noted.

Run a probe, then tick it and note the date and result, or move it to **Failed**
with what happened. Delete an entry once its fix has landed and passed.

`mise -C ~/dotfiles run nono:probe` ([`nono/battle/probe.sh`](../nono/battle/probe.sh))
runs the probes marked *(auto)* and prints PASS or FAIL for each ID; it works in a
throwaway repo it creates under the first workspace root. The rest need you.

Sandboxed commands below use the profile the agents run with:

```sh
nono run --silent --profile liflig-base -- <command>
```

`<repo>` is any clone under `~/CX`, `~/CNOPS` or `~/CN-TERMINAL`.

## Sandbox: Seatbelt rules and git

- [ ] **S1. Trust-handoff files are read-only to agents.** *(auto)*
  In the sandbox, from `<repo>`:
  `touch .git/hooks/probe`, `git config --local probe.x 1`,
  `printf x >> .mcp.json`, `printf x >> .claude/settings.json`,
  `printf x >> ~/.claude/settings.json`, `mkdir -p ~/.claude/hooks/probe`.
  Pass when each fails with "Operation not permitted" and nothing changed.
  Only the regexes were tested, in Python, against 17 deny and 15 allow paths.
- [ ] **S2. Ordinary git work still writes.** *(auto)* In the sandbox, in `<repo>`:
  stage and commit a scratch change on a throwaway branch, then
  `git clone --depth 1 https://github.com/jonasws/dotfiles <scratch>/d` and
  `git -C <scratch>/d config --local probe.x 1`.
  Pass when all succeed: the denies cover the workspace roots only, not
  scratch clones, `.git/index` or objects.
- [ ] **S3. Agent commits are signed.** *(auto)* After S2's commit:
  `git log -1 --show-signature`. Pass when it shows a good SSH signature by
  the agent key; `GIT_CONFIG_COUNT=9` in the profile's `set_vars` is what sets
  this, now that the Claude settings copy drops `GIT_CONFIG_*`.
- [ ] **S4. SSH remotes go over HTTPS.** *(auto)* In the sandbox: `git fetch` in a
  repo whose remote is `git@github.com:…`. Pass when it fetches without an
  SSH prompt or key.
- [ ] **S5. `launchctl` cannot start work outside the sandbox.** *(auto)* In the sandbox:
  `launchctl submit -l nono.probe -- /usr/bin/touch /tmp/nono-escaped`, then
  outside: `test -e /tmp/nono-escaped && echo ESCAPED`.
  Pass when `launchctl` is refused and nothing is printed. If it escapes,
  clean up with `launchctl remove nono.probe` and treat it as a gap.
- [ ] **S6. Cross-session messages.** A session outside nono runs with
  `crossSessionInbound: hold`; sandboxed agents get `accept`. From a sandboxed
  agent, `SendMessage` to a session outside nono. Pass when it is held for
  you, not delivered into the turn. Then send from outside to the sandboxed
  agent; pass when it arrives.
- [ ] **S7. `code.claude.com` is reachable.** *(auto)* In the sandbox:
  `curl -sS -o /dev/null -w '%{http_code}\n' https://code.claude.com/docs/en/settings`.
  Pass on 200 without an approval prompt.

- [ ] **S8. Instructions every later session loads are read-only.** *(auto)*
  In the sandbox: `touch ~/.claude/CLAUDE.md`,
  `mkdir -p ~/.claude/skills/probe`, the same under `agents`, `commands` and
  `output-styles`, and for pi `~/.pi/agent/extensions` and `AGENTS.md`.
  Pass when each fails and Claude Code still writes the rest of `~/.claude`
  (transcripts, todos). Not covered, deliberately: `~/.claude/plugins`
  (Claude Code updates plugins itself) and pi's `settings.json` (pi saves model
  changes there). A synced claude.ai skill or the `#` memory shortcut fails in a
  sandboxed session; check both once.
- [ ] **S9. Repo `.env` files are unreadable.** *(auto)* In the sandbox, in a
  repo with `.env`, `sub/.env.local` and `.env.example`: `cat` each. Pass when
  the first two fail, the example reads, and `ls` still lists `.env`. The rule
  is `file-read-data` with an allow for `.env.example`, `.sample`, `.template`,
  `.dist` and `.defaults` after it; P0 (`nono profile show`) is what checks that
  nono accepts an `allow` rule there. A test or dev server that loads `.env`
  fails inside the sandbox: that is the intent.

## Shell

`claude/CLAUDE.md` now tells agents to assume bash 4 and no longer explains
how the shell is chosen; the environment has to make that true.

- [ ] **H1. The Bash tool runs Homebrew bash.** *(auto: the binary; the Bash tool itself is manual)* In a session outside nono and
  in a sandboxed one, have the agent run `echo "$BASH_VERSION"`. Pass on 5.x
  in both. `CLAUDE_CODE_SHELL` in `settings.json`'s `env` sets it; a path that
  is missing or unreadable falls back to `$SHELL` (zsh) silently.
- [ ] **H2. Scripts find bash 5 on `PATH`.** *(auto)* `#!/usr/bin/env bash` and
  `bash <script>` take the first bash on `PATH`. From a mise task and a tuios
  pane, `command -v bash` is `/opt/homebrew/bin/bash`. Anything launchd starts
  gets `/usr/bin:/bin:/usr/sbin:/sbin` unless its plist sets `PATH`, so a bash
  script run there gets 3.2.

## Exa gate

Tested in the container against a fake upstream only.

- [ ] **E1. The LaunchAgent runs.** *(auto)* `mise run sync:nono-exa-gate`, then
  `launchctl print gui/$(id -u)/com.jonasws.nono-exa-gate | rg state` and
  `curl -sS -X POST -o /dev/null -w '%{http_code}\n' http://127.0.0.1:47811/answer`.
  Pass on `state = running` and 403.
- [ ] **E2. The key comes from the keychain under launchd.** First real search
  through the gate. Pass when it succeeds; a keychain access dialog for
  `/usr/bin/python3` may appear once. Check
  `~/.local/state/nono-exa-gate/gate.log`.
- [ ] **E3. exa.sh uses the gate.** From a sandboxed agent, run
  `exa.sh search <query> -o <file>`. Pass when the gate log shows the request and the agent
  gets results.
- [ ] **E4. Direct Exa is refused.** *(auto)* In the sandbox:
  `curl -sS https://api.exa.ai/search`. Pass when nono refuses the host.
- [ ] **E5. Cache-only fetch, and the shape of a miss.** From a sandboxed
  agent, `exa.sh contents <url> -o <file>` on a cached page (a popular docs page), then on a
  page Exa cannot have (a fresh gist). Pass when the first returns text with
  no prompt and the second raises a tuios `ask-human` in the agent's pane.
  This also checks the assumption that `maxAgeHours: -1` returns a miss as a
  per-URL error status, which the gate keys on.
- [ ] **E6. Answering the prompt.** Answer "No": `exa.sh` exits 3 and
  names the URL with `NOT_CACHED_AND_NOT_ALLOWED`. Answer "Fetch live": it gets the page.
- [ ] **E7. Pane lookup.** In E5, the question names the right pane. The gate
  finds it with `lsof` on the caller's port, then `ps` ancestors, then
  `tuios call resolve-pane`; any of the three may behave differently under
  launchd.
- [ ] **E8. `agent_run` is refused cleanly.** From a sandboxed agent, call
  `agent_run`. Pass when it fails at once with 403 and the agent continues
  with search and fetch, as find-docs and the researcher now say.

## Docs: local source and Context7

- [ ] **D1. `forge:maven` on a real repo.** In a CX repo that pulls from
  GitHub Packages or Nexus: `mise -C ~/dotfiles run forge:maven`. Pass when it
  ends with BUILD SUCCESS and lists few or no libraries without sources.
  Tested on a public two-module project only.
- [ ] **D2. LSP opens a dependency's source.** In a Kotlin repo after D1, the
  `LSP` tool's `goToDefinition` on a library call. Pass when it lands in the
  library's source, not a decompiled stub.
- [ ] **D3. MCP OAuth inside nono.** Start a sandboxed agent and use the
  superlogical MCP. Pass when its OAuth flow completes or its token is
  reused, without an approval for an unknown host.
- [ ] **D4. Context7's real headers.** *(auto: printed as INFO)* Outside the sandbox, with the key:
  `curl -sSG -D - -o /dev/null https://context7.com/api/v2/libs/search -H "Authorization: Bearer $CONTEXT7_API_KEY" --data-urlencode libraryName=http4k`.
  Record `Cache-Control`, any `ETag` or `Last-Modified`, and the
  `RateLimit-*` names. The cache assumes no validators and `max-age=0`, which
  was seen only on a 429. If a 200 carries an ETag or a useful `max-age`,
  revisit `context7.sh`.
- [ ] **D5. `context7.sh` on macOS.** *(auto: the curl version)* `curl --version` is 7.84 or later
  (`%header{}`). Run the same `context` query twice. Pass when the second is
  instant and makes no call; `~/.cache/context7/<hash>.json` exists. This
  also exercises `shasum` and BSD `find -mmin`. Tested on Linux against a stub.
- [ ] **D6. The cache inside the sandbox.** *(auto)* From a sandboxed agent, one
  `context7.sh context …` call. Pass when
  `~/.cache/agents/context7/<hash>.json` and
  `~/.cache/agents/context7/docs/<library>/<hash>.md` appear.
- [ ] **D7. What `context` returns.** Open a markdown copy from D6. Pass when
  the body is readable markdown. If Context7 returned JSON, it is wrapped in a
  fence, and qmd will index it poorly; then pass `type=txt` (or what the API
  guide names) or extract the text in `write_markdown`.

## Docs: qmd index

Authored only; nothing here has run.

- [ ] **Q1. qmd installs.** `mise install` after the `npm:@tobilu/qmd` line in
  `mise-global/config.toml`; `brew install sqlite`. Watch for aube refusing a
  dependency without provenance (better-sqlite3 and node-llama-cpp build
  native code), as happened with chromium-bidi. Pass when `qmd status` runs.
- [ ] **Q2. `forge:docs-index` runs.** `mise -C ~/dotfiles run forge:docs-index`.
  Pass when both Context7 collections are added, models download into
  `~/.cache/qmd/models`, and `qmd status` lists the documents as embedded.
- [ ] **Q3. Re-running is idempotent.** Run Q2 again. Pass when no duplicate
  collection appears (`qmd collection list`) and `qmd context add` replaced
  the description rather than adding a second one. The script greps
  `qmd collection list` output for the name, whose format is unchecked.
- [ ] **Q4. Cost on this Mac.** Time `qmd embed -f`, then
  `qmd search 'server filter'`, `qmd vsearch 'how do I add a filter'` and
  `qmd query 'how do I add a filter'`, and note peak memory in Activity
  Monitor. The estimates were: embed about a minute per 1,000 chunks,
  `search` milliseconds, `vsearch` under a second, `query` 3 to 10 seconds,
  2 to 3 GB of memory.
- [ ] **Q5. How agents reach the index.** Decide between running `qmd search`
  inside the sandbox (needs read access to `~/.cache/qmd`, and Metal under
  Seatbelt for `vsearch` and `query`) and a `qmd mcp --http` daemon outside it
  on localhost, like the Exa gate. Probe the first:
  `nono run … -- qmd search 'filter' -c context7-host`. Then add the chosen
  route to find-docs: search past answers before a new Context7 call.
- [ ] **Q6. Planted answers.** The `context7-agents` collection is written
  from inside the sandbox, so one agent can plant a file that another later
  finds. Decide whether to index it at all, index it only for the agent's own
  repo, or rebuild the markdown from the JSON cache in the forge task.

## Failed

Nothing yet.

## Known gaps (not probes)

Open sandbox gaps from the same review, tracked here so they are not lost:

- The Lima VM's containers have open internet.
- `~/.claude/plugins` and pi's `settings.json` stay writable (see S8), as do a
  repository's own `CLAUDE.md`, `AGENTS.md` and `.claude/skills`: changes there
  go through git review.
- Secrets in files other than `.env*` (`application-local.yml`, `.envrc`) stay
  readable.
- "Allow this session" on an unknown host opens a blind tunnel for the session.
- S3 reads reach buckets in other people's accounts.
