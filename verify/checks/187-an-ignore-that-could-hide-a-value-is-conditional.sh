# title: an ignoreDifferences that reaches annotations or labels only matches the empty map
# origin: new in v3 — 2026-09-04, measured on the instance from the clean install
check() {
# MEASURED 2026-09-04. The `kyverno` App had eleven CRDs OutOfSync since
# the installation was born, and the whole difference was that chart
# 3.8.1 renders `annotations: {}` and `labels: {}` on the CRDs of the
# new policies.kyverno.io group — reproduced with `helm template`
# outside the cluster, and not reachable from crds.annotations or
# crds.customLabels. The apiserver drops an empty map, so desired never
# equals live and nothing ever closes.
#
# The cure is an ignoreDifferences, and the cure is where the danger is:
# `/metadata/annotations` as a jsonPointer would close the light AND
# blind it. Annotations and labels carry meaning —the tracking-id ArgoCD
# itself writes, the `aegis.dev/part-of` this artifact selects on— so an
# unconditional ignore there is a comparison that stops comparing.
#
# What the artifact needs is only the empty case, and jq can say exactly
# that: `select((.annotations | length) == 0)`. A real annotation is
# still compared; only the chart's rendering bug is forgiven.
#
# So this check does not ask whether the ignore exists. It asks that the
# ignore be UNABLE to hide a value: no jsonPointer into annotations or
# labels, and every jq path into them guarded by a condition on the map
# being empty.
D187=""
[[ -d "$AEGIS_ROOT/seed/platform/k8s" ]] || { skip "the seed ships no manifests: this check has no subject"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/187.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 187 itself failed (rc $RC) and this check measured nothing about the ignores"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D187="$D187 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/187.py" "$AEGIS_ROOT" 2>&1 >/dev/null | sed 's/__COUNT__ //')"
printf '    %s forms asked of every ignoreDifferences in the artifact, with the prose around them stripped\n' "${N:-0}"
if [[ -n "$D187" ]]; then fail "an ignoreDifferences can hide a real annotation or label:$D187"
else pass "no ignore reaches annotations or labels except when the map is empty, so a chart's rendering bug is forgiven and a real value is still compared"; fi
}
