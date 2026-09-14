# JVM tests under the Claude Code sandbox

Applies to the Vy Kotlin/Maven repos under `~/CX`, `~/CNOPS` and `~/CN-TERMINAL`, which
is nearly all JVM work on this machine.

## MockK / Mockito need the agent preloaded

Anything that gets `Instrumentation` from `ByteBuddyAgent.install()` — MockK, Mockito
inline — fails inside the Bash sandbox. Every mocking test errors with
`NoClassDefFoundError: Could not initialize class io.mockk.impl.JvmMockKGateway`.

`ByteBuddyAgent.install()` attaches an agent to the already-running JVM. On JDK 24+
self-attach is off by default, so ByteBuddy falls back to `installExternal`, which spawns
a separate attacher process — the sandbox blocks it (`Could not self-attach to current VM
using external process`). `-Djdk.attach.allowAttachSelf=true` moves it onto the
in-process path, which then fails on the macOS attach channel (`Error during attachment
using: AttachmentProvider$Compound`). `-XX:+EnableDynamicAgentLoading` changes nothing.
Same family as `/bin/ps: Operation not permitted` under this sandbox.

Fix is to load the agent at JVM startup so no attach happens — `byte-buddy-agent.jar`
declares `Premain-Class: net.bytebuddy.agent.Installer`, so `ByteBuddyAgent.install()`
finds `Instrumentation` already there.

One-off:

```
mvn test -DargLine="-javaagent:$HOME/.m2/repository/net/bytebuddy/byte-buddy-agent/<ver>/byte-buddy-agent-<ver>.jar"
```

Permanent, no hardcoded version or path — add `maven-dependency-plugin` with the
`properties` goal, then in surefire:

```xml
<argLine>-javaagent:${net.bytebuddy:byte-buddy-agent:jar}</argLine>
```

Worth doing regardless of the sandbox; JDK 24+ disables dynamic agent loading in CI too.
Verified 2026-09-14 in cn-cnops-journey on Zulu JDK 25.0.4.1 with MockK 1.14.11: 498 run
/ 329 errors before, 505 run / 0 errors after. Already applied there.

## Testcontainers against colima

`~/.config/colima/default/docker.sock` is in `sandbox.network.allowUnixSockets`, so the
Docker API works from a sandboxed command. Two things still bite:

- `TESTCONTAINERS_HOST_OVERRIDE` must be `127.0.0.1`. The colima VM IP (192.168.64.6)
  answers `Operation not permitted` on every port from inside the sandbox, while colima's
  forwarded ports are reachable on loopback.
- `DOCKER_HOST=unix:///Users/jonasws/.config/colima/default/docker.sock` has to be set.
  Testcontainers does not fall back to the colima docker context, and reports
  `Could not find a valid Docker environment` without it.

`colima status` is unusable from inside the sandbox: it probes
`~/.config/colima/_lima/colima/ha.sock`, which is not allowlisted, and reports
`colima is not running` even when colima is running. Use `docker info` instead — a Server
section means up, `connection refused` means down.

## Flow tests do not run under `mvn test`

Surefire sets `<excludedGroups>integration</excludedGroups>`, so `*FlowTest` classes are
failsafe's, not surefire's. Run one with:

```
mvn -pl service failsafe:integration-test failsafe:verify -Dit.test=SomeFlowTest
```

Offline in the sandbox, a sibling module dependency has to be in `~/.m2` first:
`mvn -N install -DskipTests && mvn -pl dtos install -DskipTests`.
