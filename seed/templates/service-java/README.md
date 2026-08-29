# Template `service-java` — a JVM server behind the edge

Two stages: a JDK to compile, a JRE to run. From the second it is
instantiated the template is gone from your life: what it wrote is
yours (§0.3).

## It does NOT instantiate as it ships, and here is what it costs

Neither of its two images is mirrored: no service in this tree runs on a
JVM, and images are mirrored when somebody needs one, not in advance
(`docs/protocols/images.md` §2). Instantiating this template therefore
STOPS before writing a single file, naming the first image it could not
resolve —`eclipse-temurin:21-jdk-alpine`, then
`eclipse-temurin:21-jre-alpine`— and printing the exact command that
mirrors it. Read that line off the screen rather than from here, so
there is one place it can be wrong.

Mirroring measures the digest the tag points at today, scans it
—blocking, so a red scan is a red command— and signs it. Two runs, one
per image, and then `aegis app new` goes through. If you want a
different JDK, ask for that one instead and change the two values in
`_FROM_IMAGES` (`libexec/aegis-app`): the platform does not pick
versions for anybody, and three Java versions are three lines in the
list.

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
