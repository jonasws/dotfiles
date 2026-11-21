---
name: maven-kotlin-builds
description: Run or fix Maven builds in the Vy Kotlin repos under ~/CX, ~/CNOPS and ~/CN-TERMINAL. Use when a dependency or plugin fails with "Cannot access ... in offline mode", or when a build behaves differently inside and outside the sandbox.
---

# Maven with Kotlin

`kotlin.compiler.daemon` is the Maven property. `kotlin.compiler.execution.strategy`
is the Gradle equivalent and is silently ignored by `kotlin-maven-plugin`.

`mvn` on PATH is `~/.local/bin/wrapped/mvn`. Unsandboxed it runs the real binary
under `fnox exec`, for the credentials `~/.m2/settings.xml` reads.

Under nono (the `liflig-agent` profile, started with `ccn`) Maven is fully
online. `LIFLIG_GITHUB_PAT` and `NEXUS_PASSWORD` hold placeholders that nono's
proxy swaps for the real credentials on the way to maven.pkg.github.com and
Nexus, which allow reads only, so `deploy` is refused there. The wrapper points
Maven at the proxy and makes the JVM trust its CA. `MAVEN_ARGS` gives the agent
its own `~/.m2/repository-agents`, with `~/.m2/repository` behind it read-only,
so artifacts already downloaded are reused. Nothing to set up; just run `mvn`.

Under Claude Code's own sandbox (`$TMPDIR` is `/tmp/claude-*`) the wrapper runs
`--offline` instead, since fnox cannot reach 1Password from there. Such a build
resolves only what `~/.m2/repository` already holds: a new dependency or a
first-time plugin fails with `Cannot access ... in offline mode`. Warm the cache
from an unsandboxed shell with `mvn dependency:go-offline` rather than editing
the wrapper. Never filter a build's output down to `ERROR`
lines — that hides exactly this class of failure, and a build that never ran
looks identical to one that passed.
