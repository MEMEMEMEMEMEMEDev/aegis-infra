# title: an environment variable a manifest sets is a name the code it configures really reads
# origin: new in v3 — 2026-09-02, three of four CPU lanes found dead in production
check() {
# MEASURED IN PRODUCTION 2026-09-02, and found because the operator
# noticed, not because anything reported it.
#
# The engine-cpu manifest set four variables. Two of them were names
# nothing reads:
#
#     manifest              code              consequence
#     AEGIS_IN_CLUSTER      AEGIS_EN_CLUSTER  the engine announced itself
#                                             as the LOCAL lane while
#                                             running inside the cluster
#     AEGIS_CPU_MODELS      AEGIS_MODELOS_CPU three of four lanes could
#                                             not find their weights
#
# Both dead names are the English word order of a Spanish identifier:
# the damage of a partial translation, where the manifest was moved to
# English and the code, which stays Spanish by a declared decision, was
# not. The README documented the Spanish names all along, so the docs
# were right and the manifest was wrong, which is the reverse of where
# anybody looks.
#
# What made it expensive is that NOTHING went red. The weights were on
# the volume, the engine started, `/healthz` answered 200, the pod was
# Ready 1/1, and ArgoCD called the Application Healthy. The only trace
# was three lines in a startup log saying a lane «NO cargó», and the
# platform has no gate that reads a model. Speech synthesis, vision and
# embeddings were dead for days behind a green dashboard; only the
# transcription lane worked, and only because its variable happened to
# be spelled the same in both places.
#
# So this check pairs every manifest with the sources this same seed
# ships for it, DERIVED (k8s/base/ai-system/<name>.yaml against
# ai/<name>/) so a lane added tomorrow is covered by itself, and it
# refuses any AEGIS_* setting that no source reads.
D181=""
[[ -d "$AEGIS_ROOT/seed/platform/ai" ]] || { skip "the seed ships no AI sources: this check has no pairing to make"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/181.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 181 itself failed (rc $RC) and this check measured nothing about the manifests"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D181="$D181 $hit;"
done <<< "$OUT"

read -r NP NE < <(python3 "$AEGIS_ROOT/verify/checks/181.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2, $3}')
printf '    %s manifests paired with the code they configure · %s AEGIS_ variables judged\n' "${NP:-0}" "${NE:-0}"
if [[ -n "$D181" ]]; then fail "a manifest configures something with a name nothing reads:$D181"
else pass "every AEGIS_ variable these manifests set is read by the sources the seed ships for them, so a setting cannot be inert while the pod reports Ready"; fi
}
