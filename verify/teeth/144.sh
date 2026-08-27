# teeth for check 144 (no Application ignores the image it deploys)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
CB="seed/platform/k8s/organizations/org-canary/bundle.yaml"

# the v2 ignore comes back on the canary
red_1() {
    python3 - "$AEGIS_ROOT/$CB" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "    syncOptions: [ServerSideApply=true]\n  # NO ignoreDifferences on the image"
assert t.count(old) == 1
new = "    syncOptions: [ServerSideApply=true]\n  ignoreDifferences:\n    - group: apps\n      kind: Deployment\n      jqPathExpressions:\n        - .spec.template.spec.containers[].image\n  # NO ignoreDifferences on the image"
open(p, "w").write(t.replace(old, new, 1))
PY
}
# the same ignore, written the jsonPointers way, on another App
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/core.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "      jsonPointers: [/data]          # server.secretkey etc., runtime\n"
assert t.count(old) == 1
new = old + "    - group: apps\n      kind: Deployment\n      jsonPointers: [/spec/template/spec/containers/0/image]\n"
open(p, "w").write(t.replace(old, new, 1))
PY
}
# control: an ignore on a runtime Secret field is legitimate and stays
control_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/core.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "      jsonPointers: [/data]          # server.secretkey etc., runtime\n"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, old + "    - group: \"\"\n      kind: Secret\n      name: argocd-redis\n      jsonPointers: [/data]\n", 1))
PY
}
