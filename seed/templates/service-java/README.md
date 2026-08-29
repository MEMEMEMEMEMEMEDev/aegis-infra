# Template `service-java` — a JVM server behind the edge

Two stages: a JDK to compile, a JRE to run. It stands up in one run and,
from that second on, the template is gone from your life: what it wrote
is yours (§0.3).

## Before it will instantiate

Neither the JDK nor the JRE is mirrored yet: no service in this tree
runs on a JVM, and images are mirrored when somebody needs one, not in
advance. Instantiating stops with the exact command that asks for each
of them. That is the mechanism working, not a bug.

## What you change

- **`src/App.java`** — your app. It starts as the JDK's own HTTP server
  and nothing else: an empty dependency tree cannot rot.
- **`tests/AppTest.java`** — plain assertions with a `main`, run inside
  the build. It is the image's only gate: the canonical Jenkinsfile does
  not run tests, so a red test here is the one thing that stops a bad
  image from existing.
- **The build** — `javac` over a file list, with no egress. Adopting
  Maven or Gradle means first deciding how a tenant build reaches a
  package repository from inside the cluster.

## What you do not change, and why

- **The memory numbers** — 256Mi/512Mi, against 32Mi/64Mi in the Go
  template. A JVM given those smaller ones is OOM-killed while it
  reserves the heap and loops in CrashLoopBackOff with no message of its
  own. The contract carries a commented `tamano:` line saying so, ready
  for the day that field exists.
- **`-XX:MaxRAMPercentage` instead of `-Xmx`** — the JVM reads the
  cgroup limit, so one number governs both pod and heap. Two numbers
  drift, and the drift is fatal.
- **Port 8080 and `USER 65532:65532`** — the tenant NetworkPolicy
  admits edge -> 8080 only, and PSS restricted rejects a non-numeric
  user. Listen on 0.0.0.0: the probe comes from outside the process.
- **The two `FROM` lines, the digest marker and the public route** — the
  first are resolved against the internal registry at instantiation; the
  pipeline writes the second; the platform derives the third.
