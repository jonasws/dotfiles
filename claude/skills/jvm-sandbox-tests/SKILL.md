---
name: jvm-sandbox-tests
description: Run or debug JVM tests in the Vy Kotlin/Maven repos under ~/CX, ~/CNOPS and ~/CN-TERMINAL. Use when a mocking test throws JvmMockKGateway or ByteBuddy attach errors, when Testcontainers cannot find a Docker environment, or when a *FlowTest does not run under mvn test.
---

# JVM tests in the Vy Kotlin/Maven repos

Applies to the Vy Kotlin/Maven repos under `~/CX`, `~/CNOPS` and `~/CN-TERMINAL`, which
is nearly all JVM work on this machine.

## MockK / Mockito need the agent preloaded

Anything that gets `Instrumentation` from `ByteBuddyAgent.install()` — MockK, Mockito
inline — can fail with
`NoClassDefFoundError: Could not initialize class io.mockk.impl.JvmMockKGateway`.

`ByteBuddyAgent.install()` attaches an agent to the already-running JVM. On JDK 24+
self-attach is off by default, so ByteBuddy falls back to `installExternal`, which spawns
a separate attacher process (`Could not self-attach to current VM using external
process`). `-Djdk.attach.allowAttachSelf=true` moves it onto the in-process path, which
can then fail on the macOS attach channel (`Error during attachment using:
AttachmentProvider$Compound`). `-XX:+EnableDynamicAgentLoading` changes nothing.

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

JDK 24+ disables dynamic agent loading in CI too, so this is worth doing anyway.
Verified 2026-09-14 in cn-cnops-journey on Zulu JDK 25.0.4.1 with MockK 1.14.11: 498 run
/ 329 errors before, 505 run / 0 errors after. Already applied there.

## Testcontainers

The environment is already set for Testcontainers: `DOCKER_HOST`,
`TESTCONTAINERS_HOST_OVERRIDE` and `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` (for Ryuk), and
registry credentials. Run the tests; do not set or change these.

- `docker info` tells whether Docker is up: a Server section means up, `connection
  refused` means down. When it is down, tell the user to run `mise run lima:agents`.
- The repos are mounted read-only into Docker. A container cannot write back to the repo
  through a bind mount; copy files out with `docker cp`, or let the test write to its own
  build directory.
- Containers cannot open connections to the Mac, so a container cannot call a service
  that runs on the Mac outside Docker.

## Flow tests do not run under `mvn test`

Surefire sets `<excludedGroups>integration</excludedGroups>`, so `*FlowTest` classes are
failsafe's, not surefire's. Run one with:

```
mvn -pl service failsafe:integration-test failsafe:verify -Dit.test=SomeFlowTest
```

A sibling module dependency has to be in the local repository first:
`mvn -N install -DskipTests && mvn -pl dtos install -DskipTests`.
