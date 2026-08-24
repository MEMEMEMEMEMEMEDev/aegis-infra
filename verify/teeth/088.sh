# teeth for check 088 (the signature's scope is declared by LABEL)
#
# The incident of 2026-07-27: the ClusterPolicy scoped
# `namespaces: [org-personal]`. org-portafolio was created, something
# was deployed there, and that organization was born OUTSIDE signature
# verification. There was no error and no warning: the policy simply
# was not looking at it, and an unsigned public image was admitted with
# the whole board green.
#
# A list can only name what already exists; the label is carried by
# each tenant's bundle, so the coverage arrives with the organization.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
# the label selector is replaced by the namespace list that the
# incident proved insufficient
t = re.sub(r'(?m)^(\s*)namespaceSelector:\n(?:\1  .*\n)+',
           lambda m: f"{m.group(1)}namespaces: [org-canary]\n", t, count=1)
open(p, "w").write(t)
PY
}
