# title: a build is skipped because the registry holds the image, not because a file says it was built
# origin: new in v3 — 2026-09-02, from the install-from-zero pass
check() {
# MEASURED 2026-09-01, and it is the normal state of a NEW instance
# rather than an exotic one.
#
# Phase 87 decides whether to build each AI image by reading its row in
# ai-system/kustomization.yaml: a digest of sixty-four zeros means «not
# built yet», anything else means «done». That reading is cheap and it
# was wrong, because a pinned row and a present image are two different
# facts and only one of them is about this installation:
#
#   · the seed ships rows, and every instance is born with an EMPTY
#     registry — the row is honest and the image does not exist here;
#   · a restored kustomization, a re-created registry or a garbage
#     collection all leave the same shape behind;
#   · and the image can be present and UNSIGNED, which is worse than
#     absent: it pulls and Kyverno denies it at admission.
#
# In all three the phase went green having installed nothing. Nothing
# failed HERE — the failure surfaced later, as a pod stuck pulling or
# an admission denial, several steps away from the phase that caused
# it, and that distance is the whole cost of the defect.
#
# The precedent already existed in the artifact and nobody had joined
# it up: phase 80 skips the canary's build only after `cosign verify`
# answers over this registry, by direct IP and against this
# installation's own key. This check asks phase 87 for the same
# sentence — read the pinned digest, ask THIS registry whether it holds
# it signed, and only then skip.
#
# The asymmetry is the reason to prefer rebuilding when unsure:
# skipping wrongly costs a green phase that installed nothing, and the
# operator pays it in a diagnosis far from here. Rebuilding wrongly
# costs a build.
D174=""
P87="$AEGIS_ROOT/init/phases/87-ai.sh"
[[ -f "$P87" ]] || { skip "there is no 87-ai.sh: this check has no subject"; return; }
grep -qE '(^|[^#])jenkins_build_retry' "$P87" || { skip "phase 87 fires no builds"; return; }

# The scan is python and lives in its own file, for the two reasons
# this house has already paid for: a scanner that dies in silence turns
# a check green (166), and a grep over a file that documents its own
# defect accuses the fix (161, 163, 165, 166, 167, 168). It drops every
# comment line before it looks at anything, and it reasons about ORDER
# — what the phase does before it decides not to work.
OUT="$(python3 "$AEGIS_ROOT/verify/checks/174.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 174 itself failed (rc $RC) and this check measured nothing about the skip"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D174="$D174 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/174.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"
printf '    %s facts asked of the skip: it verifies, it verifies first, it verifies THAT digest, and it can\n' "${N:-0}"
if [[ -n "$D174" ]]; then fail "phase 87 can skip a build it never made:$D174"
else pass "phase 87 skips a build only after cosign verifies, against this installation's own key and its own registry, that the digest the row pins is actually there and signed"; fi
}
