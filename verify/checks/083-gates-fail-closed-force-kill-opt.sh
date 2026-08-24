# titulo: gates fail-closed force-kill: opt-in, no silenciosos, razón correcta (W-08)
# origen: verify-static.sh (v2) ══ 83
check() {
D83=""
F80FC="$(nc "$FASES/80-supply-chain.sh")"
echo "$F80FC" | grep -q 'AEGIS_VALIDATE_FAILCLOSED' \
    || D83="$D83 los gates fail-closed no son opt-in (crashearían cada bootstrap);"
echo "$F80FC" | grep -q '_failclosed_gates' \
    || D83="$D83 falta la función _failclosed_gates;"
echo "$F80FC" | grep -q -- '--grace-period=0' \
    || D83="$D83 no hay crash DURO (--grace-period=0 --force) del admission controller;"
echo "$F80FC" | grep -Eq '"failclosed[^"]*" skipped' \
    || D83="$D83 los gates omitidos no se registran como skipped (silenciosos — EV-08);"
echo "$F80FC" | grep -q 'failed calling webhook' \
    || D83="$D83 no asserta que el rechazo sea por el webhook caído (falso fail-closed por PSS/quota);"
echo "$F80FC" | grep -q 'failclosed-argocd-admite' \
    || D83="$D83 falta el gate de que argocd ADMITE (blast radius acotado);"
if [[ -n "$D83" ]]; then fail "failclosed:$D83"
else pass "fail-closed: opt-in por flag, crash duro, org-canary rechaza por webhook, argocd admite, skipped registrado"; fi
}
