---
name: maven-kotlin-builds
description: Run or fix Maven builds in the Vy Kotlin repos under ~/CX, ~/CNOPS and ~/CN-TERMINAL. Use when a build hits "Operation not permitted" on the Kotlin daemon directory, when a dependency or plugin fails with "Cannot access ... in offline mode", or when deciding whether to reach for -Dkotlin.compiler.daemon=false.
---

# Maven with Kotlin

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

`mvn` on PATH is `~/.local/bin/wrapped/mvn`. Outside the sandbox it runs the real
binary under `fnox exec`, for the credentials `~/.m2/settings.xml` reads. Inside
the sandbox it recognises `$TMPDIR` and runs `--offline` with no wrapper at all,
since fnox cannot reach 1Password from there.

A sandboxed build therefore resolves only what `~/.m2/repository` already holds.
A new dependency or a first-time plugin fails with `Cannot access ... in offline
mode`; warm the cache from an unsandboxed shell with `mvn dependency:go-offline`
rather than editing the wrapper. Never filter a build's output down to `ERROR`
lines — that hides exactly this class of failure, and a build that never ran
looks identical to one that passed.
