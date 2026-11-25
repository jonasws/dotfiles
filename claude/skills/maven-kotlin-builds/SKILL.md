---
name: maven-kotlin-builds
description: Run or fix Maven builds in the Vy Kotlin repos under ~/CX, ~/CNOPS and ~/CN-TERMINAL. Use when a dependency, plugin or repository fails to resolve, when authentication to GitHub Packages or Nexus fails, or when the Kotlin compiler misbehaves under Maven.
---

# Maven with Kotlin

`kotlin.compiler.daemon` is the Maven property. `kotlin.compiler.execution.strategy`
is the Gradle equivalent and is silently ignored by `kotlin-maven-plugin`.
`MAVEN_ARGS` already sets `-Dkotlin.compiler.daemon=false`: the detached daemon
outlives the build and is the wrong process to hold the project's files.

Run `mvn` as it is. `~/.m2/settings.xml` reads the passwords for GitHub Packages
(`github`, `LIFLIG_GITHUB_PAT`) and Nexus (`vy-nexus`, `NEXUS_PASSWORD`) from the
environment, and the environment already has what it needs. `MAVEN_ARGS` and
`MAVEN_OPTS` carry the rest (proxy, truststore, local repository); do not
override them, and do not pass `-s` or `-gs`.

Reading from GitHub Packages and Nexus works. Publishing to them (`deploy`) does
not: tell the user the command and leave it to them.

When resolution fails, read the whole error before changing anything:

- `401`/`403` from maven.pkg.github.com or Nexus: report it with the URL. Do not
  try other credentials or edit `settings.xml`.
- `PKIX path building failed`: the JVM does not trust the proxy's certificate.
  Tell the user to run `mise -C ~/dotfiles run nono:java-truststore`.
- `Connection refused` to `127.0.0.1`: the proxy settings point at a port with no
  proxy. Tell the user; do not remove the proxy.

Never filter a build's output down to `ERROR` lines — that hides exactly these
failures, and a build that never ran looks identical to one that passed.
