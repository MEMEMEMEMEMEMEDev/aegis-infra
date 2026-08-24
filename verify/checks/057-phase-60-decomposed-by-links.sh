# title: phase 60 decomposed by LINKS (Pattern B — story #10/#11/#12)
# origin: verify-static.sh (v2) ══ 57
check() {
# the single push→build gate coupled edge/HMAC/scan/build and died mute
# with the diagnosis in a comment. Each link, its own gate:
F60="$PHASES/60-webhook.sh"
F60_NC="$(nc "$F60")"
D57=""
for g in edge-jenkins-responde hook-jenkins-registrado delivery-push-2xx \
         build-disparado-por-webhook build-webhook-verde; do
    echo "$F60_NC" | grep -q "\"$g\"" || D57="$D57 gate $g missing;"
done
# the order IS the isolation: edge → delivery → scan → build:
L_A=$(grep -n '"edge-jenkins-responde"' "$F60" | head -1 | cut -d: -f1)
L_B=$(grep -n '"delivery-push-2xx"' "$F60" | head -1 | cut -d: -f1)
L_C=$(grep -n '"build-disparado-por-webhook"' "$F60" | head -1 | cut -d: -f1)
L_D=$(grep -n '"build-webhook-verde"' "$F60" | head -1 | cut -d: -f1)
{ [[ -n "$L_A" && -n "$L_B" && -n "$L_C" && -n "$L_D" ]] \
    && (( L_A < L_B && L_B < L_C && L_C < L_D )); } \
    || D57="$D57 gates out of order (edge=$L_A delivery=$L_B scan=$L_C build=$L_D);"
# the delivery gate looks at the STATUS on the GitHub side (push event):
echo "$F60_NC" | grep -q 'status_code' || D57="$D57 the delivery is not validated by GitHub's status_code;"
# NEXT_MB captured BEFORE the push (lastBuild race #9):
L_NB=$(grep -n 'NEXT_MB=' "$F60" | head -1 | cut -d: -f1)
L_PUSH=$(grep -n 'git push' "$F60" | head -1 | cut -d: -f1)
{ [[ -n "$L_NB" && -n "$L_PUSH" ]] && (( L_NB < L_PUSH )); } \
    || D57="$D57 NEXT_MB is not captured before the push;"
# the gates that wait must SPEAK (H7 — no diagnosis-in-a-comment):
for g in edge-jenkins-responde delivery-push-2xx build-disparado-por-webhook; do
    echo "$F60_NC" | grep -q "gate_diag \"$g\"" || D57="$D57 $g without diagnosis on failure;"
done
if [[ -n "$D57" ]]; then fail "phase 60:$D57"
else pass "phase 60 isolates edge→delivery(GitHub status)→scan→build, each link with evidence"; fi
}
