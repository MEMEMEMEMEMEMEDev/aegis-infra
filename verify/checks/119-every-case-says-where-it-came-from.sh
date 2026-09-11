# title: every case of the console says where it came from, and a derived one replays from its base
# origin: new in v3 — 2026-09-11, the corpus of the console (plan/15) against the lesson of 2026-09-10
check() {
# WHY A CORPUS NEEDS A POLICE OF ITS OWN.
#
# The console is built driven by cases: each case is a state of the
# world, stored as the documents the CLI emitted that day, and the
# screens are written until every case renders right. That only works
# while the cases are TRUE. The day one of them is a plausible file
# somebody typed, the console is being built against a fiction — and it
# will look perfectly healthy, because everything will agree with
# everything.
#
# That is not hypothetical. On 2026-09-10 a whole session measured with
# an impeccable method against a tree 172 commits old: every single
# measurement was true of the artifact in front of it, and the artifact
# was not the product. Nothing failed. The register wrote it down as
# «the coherent and false measurement».
#
# So the corpus carries its provenance and this check reads it:
#   medido      captured from the live instance — with what, when, and
#               against which commit of aegis
#   derivado    a RECORDED mutation of a measured case, and the
#               mutation is REPLAYED here, not believed
#   sintetico   written by hand, and it has to say why the real state
#               cannot be reached
#
# The `derivado` half is the one that earns its keep: a derivation that
# does not reproduce its own base is a hand edit wearing a nicer name,
# and that is precisely how a corpus rots without anybody noticing.
D119=""
CASES119="$AEGIS_ROOT/console/cases"
[[ -d "$CASES119" ]] || { skip "there is no corpus yet ($CASES119): this check has no subject"; return; }
N119="$(find "$CASES119" -mindepth 1 -maxdepth 1 -type d | wc -l)"
(( N119 )) || { skip "the corpus directory is empty: this check has no subject"; return; }

OUT119="$(python3 "$AEGIS_ROOT/verify/checks/119.py" "$AEGIS_ROOT" 2>&1)"
RC119=$?
if (( RC119 != 0 )); then
    fail "the reader of the corpus itself failed (rc $RC119) and nothing was measured about provenance: $OUT119"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D119="$D119 $hit;"
done <<< "$OUT119"

printf '    %s case(s) in the corpus\n' "$N119"
if [[ -n "$D119" ]]; then
    fail "the corpus of the console cannot vouch for itself:$D119"
else
    pass "every case declares its provenance, every measured one says what produced it and when, and every derived one replays from its base"
fi
}
