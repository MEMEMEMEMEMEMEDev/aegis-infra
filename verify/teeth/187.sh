# teeth of check 187 — an ignoreDifferences that reaches annotations or
# labels only matches the empty map.

_187() { python3 - "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml" "$@"; }

# The shortcut: drop the condition and ignore the field outright. The
# light goes green and every annotation on every CRD —the tracking-id
# included— stops being compared.
red_1() {
    _187 <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
viejo = "        - '.metadata | select((.annotations | length) == 0) | .annotations'\n"
assert s.count(viejo) == 1, "the conditional expression could not be located"
open(p, "w", encoding="utf-8").write(s.replace(viejo, "        - '.metadata.annotations'\n", 1))
PYEOF
}

# The same shortcut in the other form: a jsonPointer, which cannot carry
# a condition at all.
red_2() {
    _187 <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r"      jqPathExpressions:\n        - '\.metadata \| select\(\(\.annotations[^\n]*\n"
              r"        - '\.metadata \| select\(\(\.labels[^\n]*\n", s)
assert m, "the conditional block could not be located"
open(p, "w", encoding="utf-8").write(
    s.replace(m.group(0), "      jsonPointers: [/metadata/annotations, /metadata/labels]\n", 1))
PYEOF
}

# Conditional, but on the wrong thing: it matches by name instead of by
# the map being empty, so a CRD's real annotations are hidden anyway.
red_3() {
    _187 <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
viejo = "        - '.metadata | select((.labels | length) == 0) | .labels'\n"
assert s.count(viejo) == 1
nuevo = "        - '.metadata | select(.name != \"nada\") | .labels'\n"
open(p, "w", encoding="utf-8").write(s.replace(viejo, nuevo, 1))
PYEOF
}

# control: the PROSE that explains the danger, naming /metadata/annotations
# in the very words the scanner looks for. Comments are stripped before
# reading precisely so a paragraph is neither mistaken for a declaration
# nor able to stand in for one.
control_1() {
    _187 <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "      jqPathExpressions:\n        - '.metadata | select((.annotations | length) == 0) | .annotations'\n"
nota = ("    # note: NOT jsonPointers: [/metadata/annotations, /metadata/labels],\n"
        "    # which would hide a real value.\n")
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, nota + anchor, 1))
PYEOF
}

# control: a third empty map forgiven the same correct way. Growing the
# list conditionally is how this is maintained, not a defect.
control_2() {
    _187 <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "        - '.metadata | select((.labels | length) == 0) | .labels'\n"
extra = "        - '.spec | select((.versions | length) == 0) | .versions'\n"
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, anchor + extra, 1))
PYEOF
}
