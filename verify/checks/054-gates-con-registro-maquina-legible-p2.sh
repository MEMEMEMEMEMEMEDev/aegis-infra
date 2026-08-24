# title: gates con registro máquina-legible (P2.13 in-VM)
# origen: verify-static.sh (v2) ══ 54
check() {
D54=""
GR_BODY="$(body_of _gate_record "$LIBS/common.sh")"
[[ -n "$GR_BODY" ]] || D54="$D54 falta _gate_record;"
echo "$GR_BODY" | grep -q 'gates.jsonl' || D54="$D54 no escribe gates.jsonl;"
echo "$GR_BODY" | grep -q '|| true' \
    || D54="$D54 el registro puede voltear un gate (debe ser best-effort);"
for fn in gate gate_diag; do
    BODY54="$(awk "/^${fn}\(\)/,/^\}/" "$LIBS/common.sh")"
    (( "$(echo "$BODY54" | grep -c '_gate_record')" >= 2 )) \
        || D54="$D54 $fn no registra pass Y fail;"
done
if [[ -n "$D54" ]]; then fail "registro de gates:$D54"
else pass "gate/gate_diag registran pass+fail+duración en gates.jsonl (diagnóstico sin parsear ANSI)"; fi
}
