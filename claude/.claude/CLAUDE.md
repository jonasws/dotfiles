## CLI tool preferences

Prefer these tools over their POSIX equivalents. Examples are load-bearing.

## Search & file tools

Non-default tools; reach for them deliberately. Match tool to question shape, not a fixed order.

| Question shape | Tool |
|---|---|
| Structure on a resolved symbol: who calls X, blast radius, what implements it | `LSP` tool: `findReferences`, `incomingCalls`/`outgoingCalls`, `goToImplementation` |
| Structure ranked across a repo: what to read first, does an impl already exist | `ripwire` (CLI on PATH; the `ripwire-*` skills) — **not Kotlin** |
| "where is X", "how does Y work" — semantic, no exact identifier in hand | `semble` (MCP) |
| Match depends on syntax shape, or a rewrite | `ast-grep -p '<pat>' -l <lang>` (`-U` applies) |
| Literal/regex text, path lookup, repeated in one repo | fff MCP: `grep`, `find_files`, `multi_grep` |
| One-off search outside a git repo | `rg` / `fd` (never `find`, never `grep` CLI) |

- LSP answers from the compiler's own resolution, so prefer it over ripwire on any
  language a server is enabled for (Kotlin, Rust, TypeScript). ripwire infers edges
  from tree-sitter; LSP knows them. LSP needs a file and a position, so it answers
  "who calls THIS", never "what matters in this repo".
- **ripwire does not parse Kotlin.** `.kt` and `pom.xml` are both `unsupported-ext`,
  so a Kotlin tree indexes zero symbols and every graph verb returns an honest
  nothing. On Kotlin the structure lane is LSP; semble, fff and ast-grep are
  unaffected. Supported: C/C++, Python, TS/JS, Java, Ruby, PHP, Lua, Elixir, Bash,
  Go, Rust, Swift, C#, JSON/TOML/YAML, Markdown.
- ripwire and semble overlap only on the cold "where do I start" question, and
  answer it differently: ripwire ranks the symbol graph and gives callers,
  callees and impact; semble matches meaning when no identifier is known yet.
  Prefer ripwire once a symbol name exists; semble when only the behavior does.
- ripwire does not compete with fff or ast-grep. It indexes symbols and edges,
  never raw text or syntax patterns, so a literal search still goes to fff and a
  shape-dependent match or rewrite still goes to ast-grep.
- semble chunks are function-scoped with no caller or import context. Read the
  full file (or ±80 lines) before reasoning about a change. Locators, not context.
- fff holds a warm index per repo — pays off from the second search.
  `multi_grep` for N identifiers in one call.
- `sd` over `sed` for find & replace: global by default, no BSD `-i ''` quirk.
  Literal `$` is `$$`. Fall back to `sed`/`awk` only for line-addressed ops.

## Maven with Kotlin

Run Maven plainly — `mvn test`. The Kotlin compile daemon works inside the sandbox
because `~/Library/Application Support/kotlin` is in `sandbox.filesystem.allowWrite`
and `allowLocalBinding` is on for the daemon's RMI port.

If a build fails with
`java.nio.file.FileSystemException: ~/Library/Application Support/kotlin/daemon/... Operation not permitted`,
that allowWrite entry is missing. Restore it rather than reaching for
`-Dkotlin.compiler.daemon=false`; the flag is a fallback for a shell whose sandbox
you do not control, and it costs a cold compiler on every invocation. Never set it
in a pom or `.mvn/maven.config` — that slows every build, CI's included, to work
around one shell.

`kotlin.compiler.daemon` is the Maven property. `kotlin.compiler.execution.strategy`
is the Gradle equivalent and is silently ignored by `kotlin-maven-plugin`.

`mvn` on PATH is `~/.local/bin/wrapped/mvn`, which runs the real binary under
`fnox exec` for the credentials `~/.m2/settings.xml` reads. fnox locates its daemon
socket under `$TMPDIR`, and the sandbox rewrites `$TMPDIR` per session, so the
wrapper falls back to `--no-daemon` when no daemon answers. Symptom if that probe
is ever removed: `Configuration error: fnox daemon did not become ready`, and
Maven never runs at all — so never filter a build's output down to `ERROR` lines
that would hide it.

## Commit messages

Indent the body with 2 spaces (from line 2 and below).

## Code comments

Do not add comments of these kinds — they are self-shaming, not useful to whoever
reads the code later:

- **Unnecessarily verbose** comments that restate what the code already says.
- Comments that **mention mistakes made along the way** that are just part of the
  current work-in-progress (e.g. "removed X because it broke Y earlier", "no longer
  using Z"). The final code stands on its own; the detour is not part of it.

Comment the non-obvious *why* when it genuinely helps a future reader; skip the rest.
