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
# And the third outcome, which is the one that rots quietly. A gate with
# nothing to look at under this edge has to leave a line SAYING so: a
# gate that stops being written disappears from gates.jsonl, and a
# missing line reads exactly like a green one three months later. What
# is demanded is that it records, and that what it records is NEITHER
# pass NOR fail — recording it as a pass is the lie this whole file
# exists to prevent.
GNS_BODY="$(body_of gate_no_subject "$LIBS/common.sh")"
if [[ -z "$GNS_BODY" ]]; then
    D54="$D54 gate_no_subject missing: a gate with no subject has no way to say so;"
else
    echo "$GNS_BODY" | grep -q '_gate_record' \
        || D54="$D54 gate_no_subject does not record: the gate would vanish from gates.jsonl;"
    echo "$GNS_BODY" | grep -qE '_gate_record[[:space:]]+"[^"]*"[[:space:]]+(pass|fail)([[:space:]]|$)' \
        && D54="$D54 gate_no_subject records pass or fail: not being able to look is not the same as being fine;"
    echo "$GNS_BODY" | grep -qi 'not an approval' \
        || D54="$D54 gate_no_subject does not say out loud that it is a notice and not an approval;"
fi

if [[ -n "$D54" ]]; then fail "gate record:$D54"
else pass "gate/gate_diag record pass+fail+duration, and gate_no_subject records the third outcome as itself"; fi
}
