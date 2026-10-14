# hello-aegis — the aegis platform canary

DISPOSABLE REPO, created and seeded automatically by `aegis init`
(phase 12) and marked with a topic so a re-run reuses it. The init and
the platform WRITE to it: the pipeline builds every push, scans it,
signs it by digest and commits the digest into `k8s/overlays/dev/`
(the write-back), which ArgoCD's `hello-aegis` Application deploys.
Do not put anything that matters in here. It is re-seeded by the next
bootstrap.

It exists to prove the whole path, once per instance: phase 70 proves
that a commit touching only manifests does not trigger a build and that
a real build ends in a real deployment; phase 80 repoints its `FROM`s
at the mirrored bases and proves that its signed image is admitted and
an unsigned one is refused.

Structure: `main.go` + `go.mod` + `Containerfile` (a minimal app), the
`Jenkinsfile` the platform's template instantiates, and `k8s/` (base +
the dev overlay the digest is written into).
