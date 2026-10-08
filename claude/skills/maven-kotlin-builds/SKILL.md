---
name: maven-kotlin-builds
description: Run or fix Maven builds in the Vy Kotlin repos under ~/CX, ~/CNOPS and ~/CN-TERMINAL. Use when a dependency or plugin fails with "Cannot access ... in offline mode", or when a build behaves differently inside and outside the sandbox.
---

# Maven with Kotlin

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
