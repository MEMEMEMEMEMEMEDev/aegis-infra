# title: gates with a machine-readable record (P2.13 in-VM)
# origin: verify-static.sh (v2) ══ 54
check() {
D54=""
GR_BODY="$(body_of _gate_record "$LIBS/common.sh")"
[[ -n "$GR_BODY" ]] || D54="$D54 _gate_record missing;"
echo "$GR_BODY" | grep -q 'gates.jsonl' || D54="$D54 does not write gates.jsonl;"
echo "$GR_BODY" | grep -q '|| true' \
    || D54="$D54 the record can flip a gate (it must be best-effort);"
for fn in gate gate_diag; do
    BODY54="$(awk "/^${fn}\(\)/,/^\}/" "$LIBS/common.sh")"
    (( "$(echo "$BODY54" | grep -c '_gate_record')" >= 2 )) \
        || D54="$D54 $fn does not record pass AND fail;"
done
if [[ -n "$D54" ]]; then fail "gate record:$D54"
else pass "gate/gate_diag record pass+fail+duration in gates.jsonl (diagnosis without parsing ANSI)"; fi
}
