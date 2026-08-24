# teeth of check 005c (the canary's seed is complete)
# The org-personal → org-canary rename was left half done on 2026-07-28
# and the seed stopped starting up; this check comes from there.
red_1() { rm -f "$AEGIS_ROOT/seed/canary/k8s/base/deployment.yaml"; }
red_2() { rm -f "$AEGIS_ROOT/seed/canary/go.mod"; }
