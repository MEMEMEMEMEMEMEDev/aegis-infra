# title: starting with ZERO organizations is not a corner case
# origin: verify-static.sh (v2) ══ 87
check() {
# The two organization manifests are DERIVED by `aegis org` from
# orgs/*.yaml, and a freshly started instance has no contracts: the two
# exist with their header and without a single document. That is day
# one's normal state, not an anomaly.
#
# But `kubectl apply -f` over a file with no objects is NOT a no-op:
#
#     error: no objects passed to apply     (rc 1)
#
# and with set -e it kills phase 35. Which is to say the seed would fail
# to start for being correct. This check covers the fix's three pieces.
D87=""
APT87="$P/k8s/bootstrap/appprojects-tenants.yaml"
TEN87="$P/k8s/argocd-apps/tenants.yaml"
# 1) the two files EXIST versioned: phase 35 applies the first, and a
#    file missing there is a different and worse startup error.
for f87 in "$APT87" "$TEN87"; do
    [[ -f "$f87" ]] || D87="$D87 ${f87#"$P"/} missing (the generator derives it, but it has to exist versioned);"
done
# 2) and they arrive WITH no documents: another instance's contracts do
#    not travel.
if [[ -f "$APT87" ]]; then
    N87="$(python3 -c 'import sys,yaml; print(len([d for d in yaml.safe_load_all(open(sys.argv[1])) if d]))' "$APT87" 2>/dev/null)"
    [[ "$N87" == "0" ]] || D87="$D87 the seed's appprojects-tenants.yaml brings $N87 document(s): they are another instance's organizations;"
fi
# 3) the helper exists and phase 35 GUARDS the apply with it. It is
#    checked that the guard and the apply are on the same logical line:
#    that yaml_has_docs exists somewhere in the file does not prove it
#    protects THIS apply.
grep -q '^yaml_has_docs()' "$LIBS/common.sh" \
    || D87="$D87 yaml_has_docs missing from common.sh;"
grep -qE '^\s*if\s+yaml_has_docs\s+"\$PLATFORM_DIR/k8s/bootstrap/appprojects-tenants\.yaml"' \
     "$PHASES/35-gitops.sh" \
    || D87="$D87 phase 35 applies appprojects-tenants.yaml without asking whether it has documents;"
# 4) the THIRD derived thing, which is not a whole file but a REGION
#    (added 2026-08-22 along with the probe derivation). vmagent/
#    values.yaml is half product and half generated: `aegis-org` writes
#    one probe per organization into it, between two markers.
#
#    Here un-rendering is NOT enough and that is why this point was
#    needed. `traer` turned blog.example.com into blog.__ROOT_DOMAIN__
#    —the aegis dev seed guard passed happily, this instance's value was
#    no longer there— but the organizations' NAMES stayed. The seed was
#    left probing blog, ejemplo, portafolio and shop: four sites that do
#    not exist on a new instance, four probes permanently red and four
#    SitioDeInquilinoCaido on day one. The chronic false red, factory
#    fitted, on the product's premiere.
VMA87="$P/k8s/base/observability/vmagent/values.yaml"
if [[ ! -f "$VMA87" ]]; then
    D87="$D87 ${VMA87#"$P"/} missing;"
else
    N87S="$(python3 - "$VMA87" <<'PY'
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
i = t.find("# --- DERIVED by aegis-org (tenant probes): do not edit by hand ---")
f = t.find("# --- END DERIVED ---")
print(-1 if i < 0 or f < 0 else len(re.findall(r"^\s*-\s*job_name:", t[i:f], re.M)))
PY
)"
    [[ "$N87S" == "-1" ]] \
        && D87="$D87 vmagent/values.yaml lost the derived block's markers: without the anchor, aegis-org has nowhere to write the probes;"
    [[ "$N87S" == "0" || "$N87S" == "-1" ]] \
        || D87="$D87 vmagent/values.yaml's derived block brings $N87S probe(s): they are another instance's organizations, and on the new one they do not exist (permanently red from startup);"
fi
if [[ -n "$D87" ]]; then fail "startup with 0 organizations:$D87"
else pass "the seed's 3 derived things arrive empty (2 manifests with no documents + vmagent's probe block) and phase 35 guards its apply with yaml_has_docs"; fi
}
