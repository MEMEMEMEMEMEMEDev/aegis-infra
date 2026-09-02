# title: no runtime message tells the operator that a verb this product dispatches does not exist
# origin: new in v3 — 2026-09-02, found reviewing the seed before an install from zero
check() {
# MEASURED 2026-09-02, and the shape is worth stating because it is
# not a typo: it is prose that was TRUE when it was written and that
# the artifact then outgrew.
#
# Phase 87 refuses to fire a heavy build when the node has no room,
# and its refusal explained where the space went:
#
#     `aegis image gc` does not exist yet: the registry keeps every
#     image ever built...
#
# True when written. Then the pruner was built, `gc` joined `aegis
# image`, and nobody went back to the sentence. So the product now
# tells the operator that the tool does not exist at the exact moment
# they need it, and the operator believes it — the message comes from
# the product itself, which is the most credible source they have.
#
# This is the inverse of the hole the artifact already covers: check
# 112 asks that every command a phase INVOKES exists, and check 106
# that every command the DOCS cite exists. Both ask «is the thing you
# named real?». Neither asks «is the thing you said was missing still
# missing?», and a false negative claim is worse than a false positive
# one: a name that does not resolve fails loudly the first time
# somebody types it, while «it does not exist» is never typed at all.
#
# So this check reads what the operator can actually be SHOWN — the
# non-comment lines of the phases, the commands and the libraries —
# and refuses any claim of absence about a verb the product really
# dispatches. What exists is DERIVED from libexec/ and from each
# command's own `# aegis-subcommands:` header, never from a list here:
# a check with its own roster of verbs is one more place to go stale,
# which is the very defect being hunted.
D179=""
[[ -d "$AEGIS_ROOT/libexec" ]] || { skip "there is no libexec/: nothing dispatches, so no claim about a verb can be stale"; return; }

# The scan is python and lives in its own file for the two reasons
# this house has paid for: a scanner that dies in silence turns a
# check green (166), and a grep over a file that documents its own
# defect accuses the fix (161, 163, 165, 166, 167, 168). It drops
# every comment line before looking, and the tooth keeps a control
# that is exactly such a paragraph.
OUT="$(python3 "$AEGIS_ROOT/verify/checks/179.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 179 itself failed (rc $RC) and this check measured nothing about the product's messages"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D179="$D179 $hit;"
done <<< "$OUT"

read -r NV NL < <(python3 "$AEGIS_ROOT/verify/checks/179.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2, $3}')
printf '    %s verbs derived from libexec · %s runtime lines read\n' "${NV:-0}" "${NL:-0}"
if [[ -n "$D179" ]]; then fail "the product tells the operator that something it can do does not exist:$D179"
else pass "no runtime message claims a verb is missing that libexec actually dispatches, so a refusal that names a tool names one the operator can run"; fi
}
