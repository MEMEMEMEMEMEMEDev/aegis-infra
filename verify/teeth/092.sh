# teeth for check 092 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# the subject disappears: if the check does not notice, it was not reading it
red_1() { rm -f "$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"; }

# The alert whose threshold §10 verifies disappears. Before 2026-08-26
# the loop over zero matches compared nothing and passed; now the guard
# has to name the absence.
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"          - alert: JobDeScrapeDesaparecido\n(?:            .*\n|              .*\n)+", "", t)
assert n[1] == 1, n[1]
open(p, "w").write(n[0])
PY
}
