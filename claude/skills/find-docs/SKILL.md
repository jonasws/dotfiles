---
name: find-docs
description: >-
  The single entrypoint for looking anything up outside this machine — library and
  framework docs, AWS service behavior, another project's source or changelog, and
  general web research. Routes the question to the right backend before spending a
  remote call: the Context7 API for library/SDK/CLI docs, the aws-knowledge MCP for AWS,
  the github MCP for repo-specific source and history, exa for everything else.

  Use whenever exact signatures, config options, version-specific behavior, error
  strings, release timing, or current facts matter and training data may be stale —
  including for well-known technology like React, Spring Boot, Terraform or Postgres.
  Also use for "what changed in version X", "does service Y support Z in eu-west-1",
  "how does project W implement this", "is there a library that does this", and any
  request to read or research a URL.

  WebSearch is disabled in this environment, so this skill is the only path to the
  outside. Reach for it instead of answering API details from memory.
---

# External Lookup

This skill starts where the local search ends. CLAUDE.md's tool table governs finding things in the repo — LSP for resolved symbols, semble for concepts, ast-grep for shape, fff and rg for text. Come here once the answer is demonstrably not on this machine: a version you do not have, a service whose source you cannot read, current state of the world, or the intent behind a design that source alone will not explain.

From there the only question is which door. Picking wrong costs twice: a wasted round trip, and an answer that reads as authoritative while coming from the wrong corpus — Context7 will happily return generic library prose for an AWS quota question.

## Routing table

| The question is about | Backend | Entry point |
|---|---|---|
| A named library, framework, SDK, or CLI tool — API, config, migration | Context7 | `curl` the search endpoint; `libs/search` then `context` to go deep |
| AWS — service behavior, API/CLI params, CloudFormation/CDK, regional availability | aws-knowledge MCP | `aws___search_documentation` |
| A specific repo or org (never `nsbno` — see below) — source, issues, PRs, releases, changelogs, "when did this change" | github MCP | `search_code`, `search_issues`, `list_releases` |
| Everything else — news, comparisons, ecosystem questions, "does a tool exist for X" | exa MCP | `web_search_exa` |
| Reading a URL you already have | `defuddle`, locally | `defuddle parse <url> --md -o page.md`, then grep — see [Reading a page](#reading-a-page) |

Two signals settle most cases: **is there a named artifact** (library, service, repo), and **is the answer stable documentation or a changing fact**. Documentation about a named artifact goes to Context7 or aws-knowledge; a changing fact about a named repo goes to github; anything with no named artifact goes to exa.

## Context7 — library and framework documentation

Context7 is three GET endpoints on `context7.com`, called with `curl`; there is no CLI to install. Every Bash command in a session already carries `CONTEXT7_API_KEY`: a SessionStart hook (`claude/hooks/context7-env.sh`) fetches it from fnox, so requests authenticate inside the sandbox too. In a sandboxed session, name `context7.com` on the command. Keep the curl flags as shown: `-s` drops the progress meter, `-S` still prints a one-line reason when the connection fails (plain `-s` prints nothing and exits 6, which reads like an empty result), `--fail-with-body` exits non-zero on an HTTP error while keeping Context7's one-line JSON reason, and `--max-time 30` bounds a hung request. Never add `-v` or `-i`; headers and TLS chatter are noise in context.

Two ways in, and the first match in this table decides. Count calls against the backend budget of about three: search is one call, resolving a library and then querying it is two, and each query on an ID you already hold is one.

| The question | Call | Calls |
|---|---|---|
| You hold a Context7 ID (`/org/project`): from the user, or from the `Library:` line of an earlier search result | `context` with that ID | 1 |
| A pinned version of one library | `libs/search` for its indexed versions, then `context` with the versioned ID (`/vercel/next.js/v13.5.11`); skip the resolve when you hold that ID | 2, or 1 |
| A first question, the library named or not | search, with a `library` hint when you know it | 1 |
| How two to four libraries work together | search, one `library` hint each | 1 |
| Search came back thin, wrong-library or 404 after a hint | `libs/search` to see the candidates and pick one, then `context` | 2 |

**Search** sends one question; Context7 picks the libraries, ranks snippets across them, and returns prompt-ready text with each snippet's library and source URL. It is Context7's own recommendation for a quick, grounded answer.

```bash
curl -sSG --fail-with-body --max-time 30 https://context7.com/api/v3/search -H "Authorization: Bearer $CONTEXT7_API_KEY" \
  --data-urlencode 'query=How do I write a server filter in http4k?' \
  --data-urlencode language=Kotlin
```

Hints: `library=` (a name or a Context7 ID; repeat for up to four; a name can match several libraries, as `Next.js` matches both `/vercel/next.js` and `/websites/nextjs`, so pass the ID to hold search to one), `version=` such as `15.4.0` (needs a `library` hint, and is a preference, not a pin: with the exact ID `/vercel/next.js` and `version=13.5.11`, one of four snippets still came from `canary`, where `context` on `/vercel/next.js/v13.5.11` returned only 13.5.11 sources), and `type=json` for `codeSnippets` and `infoSnippets` with per-snippet token counts, when results need filtering before they are read. A 404 (`no_documentation_found`) means nothing matched, not that the endpoint is down: rephrase, add a `library` hint, or pick the library yourself.

**Pick the library yourself** (the Context API) for follow-ups on one library, or when search picked the wrong one. Follow-ups reuse the ID a search result already named; resolve with `libs/search` only when no result has given you the right one. `libs/search` also lists the versions a library has indexed, which search does not show.

```bash
curl -sSG --fail-with-body --max-time 30 https://context7.com/api/v2/libs/search -H "Authorization: Bearer $CONTEXT7_API_KEY" \
  --data-urlencode libraryName=http4k --data-urlencode 'query=server filters' \
  | jq -r '.results[:5][] | [.id, .title, .totalSnippets, .trustScore, .benchmarkScore, ((.versions // [])[:5] | join(","))] | @tsv'

curl -sSG --fail-with-body --max-time 30 https://context7.com/api/v2/context -H "Authorization: Bearer $CONTEXT7_API_KEY" \
  --data-urlencode libraryId=/http4k/api \
  --data-urlencode 'query=How do I write a server filter?' \
  --data-urlencode language=Kotlin
```

Skip the resolve step when you hold an ID in `/org/project` form, from the user or a search result; never guess one. IDs always carry the leading `/`, and a guessed one returns `404 library_not_found`. Use the official name with its real punctuation — `"Next.js"` not `nextjs`, `"Three.js"` not `threejs` — because ranking keys off it; if the matches look wrong, try another spelling before rewording the query. Prefer the official, primary source over community forks and mirrors, then high `totalSnippets`, `trustScore` and `benchmarkScore`; when two libraries fit about equally, name both and say which you picked. A named version maps to `/org/project/<version>` (or `@<version>`), using the closest one `versions` lists; check that the snippets' source URLs carry that tag.

Pass `language` on both paths so examples in it rank first. In the repos under `~/CX`, `~/CNOPS` and `~/CN-TERMINAL` that is Kotlin, unless the file at hand is TypeScript (the `*-infra` CDK apps, web apps).

One topic per query, on either path, unless the topic is how libraries interact, which is one search with several hints. `"routing and auth and caching in Next.js"` returns shallow results for all three; three separate queries return real ones. Describe what to look up in the documentation rather than the task you are trying to finish, and keep credentials, proprietary code and personal data out of the query string.

**Errors** come back as JSON with `error` and `message`. `429` means the monthly quota is exhausted: say so, and if `CONTEXT7_API_KEY` is empty in the session, say the hook did not resolve it. Then answer from training knowledge *and mark which parts those are*. Silently degrading to memory is the failure mode that misleads. `401` means a bad key; `503` is a transient search failure worth one retry.

## aws-knowledge MCP — anything AWS

AWS docs are a distinct corpus with their own retrieval, so a Lambda or IAM question sent to Context7 or exa gets a worse answer than the dedicated server gives.

- `aws___search_documentation` first. Each result's `context` is a verbatim page chunk, not a snippet — usually enough to answer directly. Pick one `topics` value (`reference_documentation`, `troubleshooting`, `cdk_docs`, `cloudformation`, …); extra topics dilute ranking.
- `aws___read_documentation` only when the chunks genuinely lack it — a visibly truncated enumeration, or nothing on-topic after refining the query.
- `aws___retrieve_skill` when a search result carries a `skill_name`. That expands into a guided AWS workflow, and nothing else surfaces it, so it goes unused unless you reach for it deliberately.
- `aws___get_regional_availability` for "is X in eu-west-1", with exact catalog names; `aws___list_regions` resolves a region code first, which is cheaper than having a guessed one rejected.

## github MCP — source, history, and changelogs

Use when the subject is a *project* rather than a topic: how an implementation actually works, when behavior changed, whether a bug is known, what shipped in a release.

- `search_code` with bare identifiers plus `repo:`/`org:` — a code index, not a regex engine.
- `search_issues` / `search_pull_requests` before concluding something is a bug in your own code; someone usually filed it.
- `list_releases` / `get_latest_release` / `search_commits` for "when did this change" and version timing.
- `get_file_contents` once you know the path. Reading the source settles what documentation leaves ambiguous, and it is also the right move for a **dependency's behavior** — read the library's own repo rather than unpacking jars locally. `LSP` `goToDefinition` and the `idea` MCP get you there too when sources are attached.

When none of those resolve it, say so and hand the question back with what you would check next. An unanswered question the user can close in one sentence beats a plausible guess.

Never use the `gh` CLI here; it is denied and unauthenticated in this environment.

Not for the `nsbno` org: the github MCP token lacks proper access there, so a search returns empty or partial results that look like a real "not found". Those repos are internal, not outside this machine. For another service's API (endpoints, DTOs), use the `sibling-api-docs` skill and read its rendered contract rather than its source. Otherwise search the local clones under `~/CX`, `~/CNOPS` and `~/CN-TERMINAL`, and if the repo is not cloned, say so. Search the default branch rather than whatever is checked out: `git fetch origin`, then `git grep <pattern> origin/HEAD` and `git show origin/HEAD:<path>`. CLAUDE.md's GitHub section has the full recipe and when the working-tree tools are safe to use instead.

## exa MCP — the open web

The residual: no named library, no AWS service, no specific repo. Comparisons, ecosystem questions, incident writeups, vendor pages, standards, anything current.

- `web_search_exa` — describe the ideal page, not keywords: `"blog post comparing Kotlin coroutines and virtual threads for JDBC workloads"` beats `"coroutines vs virtual threads"`. State the goal in `objective` so ranking knows what to surface.
- `web_search_advanced_exa` — the same search with category filters, domain restrictions, date ranges, highlights, summaries and subpage crawling. It also returns the results' **full text untruncated** when `textMaxCharacters` is omitted, and `maxAgeHours: 0` forces a fresh crawl instead of the cached copy. So when you need the body of what you find, this one call beats searching and then fetching each hit.
- `agent_run` — genuinely multi-step research only (build a list, cross-verify across sources, enrich a table). Long-running; a single question does not need it.

## Reading a page

`defuddle` is installed, so reach for it directly — parse to a file and grep it:

```bash
defuddle parse <url> --md -o page.md    # then grep the file, never cat it
```

This is the default because of what the alternatives get wrong, not because it is cheap. Most lookups are a search for something specific — a flag, a default, a signature, whether a thing exists at all — and that fact sits wherever the page happens to put it. Any tool that returns the first N characters is answering a different question, and when the fact falls outside the window you conclude "the page doesn't document this" with nothing to indicate you were cut off. A grep over the complete text cannot produce that false negative, and it surfaces the neighbors you did not know to ask about: the same grep that found one timeout variable in a 155 KB page turned up a second one that changed the answer.

It takes HTML on stdin too (`curl -sSL <url> | defuddle parse --md`) when the fetch needs your own redirects, headers or cookies, and `--user-agent` when a site 403s the default one.

Its one blind spot is client-rendered pages: there is no JS engine, so an SPA or an interactive API reference yields a skeleton rather than the content. That failure is at least loud — `defuddle parse <url> -p wordCount` shows a few hundred words where a full API reference should run to thousands, and you escalate knowing why. Silent truncation elsewhere gives you no such signal, which is the real argument for starting here.

One escape from there:

- **`web_fetch_exa`** for the client-rendered case `defuddle` cannot reach, or several URLs in one call. Always pass `maxCharacters`: omitting it truncates at about 3000 characters — silently, mid-sentence — and no env var or config changes that default. Exa bills `/contents` per page rather than per character, so raising it costs nothing in money; what it costs is context, because this result lands in the conversation and cannot be grepped first. Around 25000 is a working figure for reading a page properly. Wanting much more than that is the signal to go back to `defuddle` and a file: one large documentation page came back as 285,798 characters, roughly 71k tokens, which is most of a context window spent on a single fetch. And whatever the cap, this is the wrong tool for "list every X", where a truncated answer is indistinguishable from a complete one.

When the URL came from a search you just ran, reconsider the order: `web_search_advanced_exa` returns each result's full text in the search call itself, so searching and then fetching each hit pays twice for what one call already had.

## When a backend misses

Crossing over is normal — a miss usually means the question was a different shape than it looked, not that the answer is unavailable.

- Context7 has no entry for the library → its GitHub repo via the github MCP (README, source, releases), then exa.
- Context7 has the library but not the detail → read the implementation with `get_file_contents`; source is ground truth.
- AWS docs describe the happy path only → exa for the real-world failure mode and writeups.
- exa surfaces a promising URL → read it properly per [Reading a page](#reading-a-page) rather than reasoning from a search snippet.

A backend that is *unreachable* is a different case from one that answers with nothing. MCP servers do fail to connect. When that happens, say which backend was unavailable, route to the next one, and mark anything the remaining backends could not confirm — the same rule as a Context7 quota error, for the same reason.

Cap each backend at about three calls. The real stop signal is information gain rather than a count: when two calls in a row return nothing that changes the answer, a third will not either. Report what you found and what stayed open.

## Reporting what you found

Name the backend and the identifier so the lookup is reproducible: the Context7 library ID (with its version when the answer depends on one), the AWS doc URL, `owner/repo` plus path or issue number, the fetched URL. If part of the answer came from training data rather than a lookup, mark that part. The point of routing through here is that the user can tell which claims were actually verified.
