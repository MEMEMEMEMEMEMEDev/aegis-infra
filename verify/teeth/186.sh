# teeth of check 186 — Kyverno's defaults are ignored wherever the
# artifact ships a policy.

_186_gen() { python3 - "$AEGIS_ROOT/lib/aegis/org.py" "$@"; }
_186_cp()  { python3 - "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml" "$@"; }

# THE STATE THE ARTIFACT WAS IN until 2026-09-04: the lesson was written
# for ClusterPolicy and never carried to the namespaced Policy that
# `tamano` introduced, so org-portafolio was born OutOfSync and stayed
# that way with nothing wrong with it.
red_1() {
    _186_gen <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r"\n    - group: kyverno\.io\n      kind: Policy\n"
              r"      jqPathExpressions:\n(?:        - '[^\n]*'\n)+", s)
assert m, "the Policy entry could not be located"
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), "\n", 1))
PYEOF
}

# The list is there and it only decorates the diff: without
# RespectIgnoreDifferences ArgoCD keeps sending the fields it says it
# ignores, and the drift never closes.
red_2() {
    sed -i 's|ServerSideApply=true, CreateNamespace=true, RespectIgnoreDifferences=true|ServerSideApply=true, CreateNamespace=true|' \
        "$AEGIS_ROOT/lib/aegis/org.py"
}

# Two lists that drift apart: the next Kyverno default gets added to one
# of them and the other reopens the hole in silence.
red_3() {
    _186_gen <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
linea = "        - '.spec.emitWarning'\n"
assert s.count(linea) == 1
open(p, "w", encoding="utf-8").write(s.replace(linea, "", 1))
PYEOF
}

# Both lists lose the very default that was measured to break it. They
# stay identical to each other, so only a check that remembers WHICH
# field it was still bites.
red_4() {
    for f in "$AEGIS_ROOT/lib/aegis/org.py" \
             "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml"; do
        sed -i "/skipBackgroundRequests/d" "$f"
    done
}

# The shortcut that makes the light go green and blinds it: ignoring the
# whole subtree hides a real change to the policy too.
red_5() {
    _186_gen <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r"(\n    - group: kyverno\.io\n      kind: Policy\n"
              r"      jqPathExpressions:\n)((?:        - '[^\n]*'\n)+)", s)
assert m, "the Policy entry could not be located"
open(p, "w", encoding="utf-8").write(
    s.replace(m.group(0), m.group(1) + "        - '.spec.rules'\n", 1))
PYEOF
}

# control: the PROSE that explains the guarantee, naming the two kinds
# and the very expressions, in the file that implements it. The scanner
# strips comments before reading precisely so a paragraph cannot be
# mistaken for a declaration — nor stand in for one.
control_1() {
    _186_gen <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "    - group: kyverno.io\n      kind: Policy\n"
nota = ("    # note: the same family the kyverno-policies App ignores on\n"
        "    # kind: ClusterPolicy, .spec.rules[].skipBackgroundRequests\n"
        "    # among them.\n")
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, nota + anchor, 1))
PYEOF
}

# control: one more Kyverno default added to BOTH lists at once. Growing
# the list correctly is how this is maintained, not a defect.
control_2() {
    for f in "$AEGIS_ROOT/lib/aegis/org.py" \
             "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml"; do
        python3 - "$f" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r"( *)- ('?)\.spec\.emitWarning\2\n", s)
assert m, "the anchor expression could not be located in %s" % p
nueva = "%s- %s.spec.evaluation.background.enabled%s\n" % (m.group(1), m.group(2), m.group(2))
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), m.group(0) + nueva, 1))
PYEOF
    done
}
