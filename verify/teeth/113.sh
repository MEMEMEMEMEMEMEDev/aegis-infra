# teeth for check 113 (the seed is a fixed point of its generator)
#
# The three mutations are the three real defects of 2026-08-25, each
# reduced to its smallest form. If any of them stops biting, the check
# went back to being what it replaced: nothing.
SEEDP="seed/platform"

# A generated artifact edited by hand. This is the everyday case: the
# file looks like any other YAML and its banner is six lines up.
red_1() {
    python3 - "$AEGIS_ROOT/$SEEDP/k8s/argocd-apps/tenants.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
# The anchor is asserted: on 2026-08-25 the first version of this
# mutation searched for a "# hash:" that this file does not carry, so
# it changed NOTHING and the tooth reported «does not bite» against a
# check that was fine. A mutation that mutates nothing tests nothing.
old = "# CreateNamespace=true:"
assert old in t
open(p, "w").write(t.replace(old, "# touched by hand\n" + old, 1))
PY
}

# The derived block's markers disappear. The stage does not write
# anything wrong — it REFUSES, and in the real chain it takes the
# stages after it with it.
red_2() {
    python3 - "$AEGIS_ROOT/$SEEDP/k8s/base/platform/jenkins/values.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "          # --- DERIVED by aegis-org (tenant jobs): do not edit by hand ---\n"
assert old in t
open(p, "w").write(t.replace(old, "", 1))
PY
}

# The declared source of truth moves and the derived artifact stays
# behind: one more hostname in edge.yaml that main.tf does not carry.
# This is the one that left grafana and ntfy without a CNAME, with
# everything green.
red_3() {
    python3 - "$AEGIS_ROOT/$SEEDP/edge.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert "\n  - ntfy\n" in t
open(p, "w").write(t.replace("\n  - ntfy\n", "\n  - ntfy\n  - status\n", 1))
PY
}

# The block between the markers is edited: it says «do not edit by
# hand» and the next run rewrites it, so what somebody wrote there is
# lost without a word.
red_4() {
    python3 - "$AEGIS_ROOT/$SEEDP/k8s/base/observability/vmagent/values.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
end = "    # --- END DERIVED ---"
assert end in t
open(p, "w").write(t.replace(end, "    # a probe added by hand\n" + end, 1))
PY
}

# A file the generator does not write: touching it must stay green, or
# the check would be forbidding every legitimate edit to the seed.
control_1() {
    printf '\n# legitimate comment on a file nobody derives\n' \
        >> "$AEGIS_ROOT/$SEEDP/k8s/base/kyverno-policies/kustomization.yaml"
}

# Inside a file the generator DOES touch, but OUTSIDE its markers: the
# rest of jenkins' values belongs to whoever maintains it.
control_2() {
    printf '\n# legitimate comment outside the derived block\n' \
        >> "$AEGIS_ROOT/$SEEDP/k8s/base/platform/jenkins/values.yaml"
}
