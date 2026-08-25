# env cert-manager — DOES NOT EXIST IN V2 (decision D6)

In v2 tofu does not manage K8s resources: ArgoCD is installed by a
direct helm install (phase 30) and GitOps owns everything from minute
one. This directory stays as a marker so the v1 reader does not go
looking for it. See PROGRESO.md D6 and docs/architecture/bootstrap.md.
