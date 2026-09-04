# title: aegis-data backs up every dumped type the catalogue declares, not only postgres
# origin: new in v3 — 2026-09-04, building the shop demo: mongodb was declared, rendered and fenced, and aegis-data could not back it up
check() {
# CHECK 156 is scoped OUT of this on purpose: it measures that the
# CATALOGUE is coherent and that the generator renders each stateful
# type. It says nothing about whether `aegis data` can actually capture
# and restore them — «libexec/aegis-data implements this contract, and
# it is out of this check's scope». This check is that scope.
#
# WHAT WENT WRONG, measured 2026-09-04. `sources()` knew one stateful
# type: postgres, by contract `tipo`, crossed against the StatefulSets
# labelled `aegis.dev/component=datos`. mongodb carries that same label.
# So the moment an organization declared mongodb, its StatefulSet read
# as «alive and undeclared» and `sources()` aborted — and it aborts for
# the WHOLE instance, so a mongo contract would have taken the backup of
# every other organization down with it. A second, quieter bug waited in
# restore(): `buckets = [p if tipo != "postgres"]` would have handed
# every mongo piece to restore_bucket.
#
# The fix is the one the catalogue was already asking for: the dump and
# restore COMMANDS live in services.yaml (`backup.dump`, `backup.restore`),
# and aegis-data runs THEM, so a fourth dumped type works without editing
# this code. This check nails down the parts that, if they regress, fail
# in the two silent ways above: a backup that captures less than it
# should, and a restore that puts a piece where it does not belong.
D188=""
DATA="$AEGIS_ROOT/libexec/aegis-data"
[[ -f "$DATA" ]] || { skip "libexec/aegis-data does not exist: this check has no subject"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/188.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 188 itself failed (rc $RC) and this check measured nothing about aegis-data"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D188="$D188 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/188.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"
printf '    %s facts asked of aegis-data, with the prose around them stripped\n' "${N:-0}"
if [[ -n "$D188" ]]; then fail "aegis-data does not serve every dumped type the catalogue declares:$D188"
else pass "aegis-data derives its dumped types from services.yaml, counts them among the declared sources so a mongo StatefulSet does not abort the run, keeps them out of the bucket path, captures and restores them through the catalogue's own templates, and weighs them as databases"; fi
}
