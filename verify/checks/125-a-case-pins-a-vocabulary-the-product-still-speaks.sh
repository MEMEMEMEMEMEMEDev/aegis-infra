# title: the vocabulary a case pins is one the product can still emit
# origin: new in v3 — 2026-09-11, the answer to «this repo does not version fixtures» (plan/15 §3)
check() {
# THE OBJECTION THIS EXISTS TO ANSWER.
#
# This repo does not version fixtures, on purpose: a sample file ages in
# silence because nothing re-derives it, and silence is the disease.
# That is why the teeth mutate a copy of the real tree instead of
# storing examples. A corpus of cases goes straight against that rule,
# and without an answer it should not have been built.
#
# The answer is the one `images.txt` already uses on third-party
# images: it FREEZES the digest, and `image-watch` asks every morning
# whether the tag moved upstream. Freeze and watch, both.
#
#   the case freezes the VALUES — and those may age without harm: «this
#   is how the world looked that day» stays true forever;
#   this check re-derives the SHAPE — the vocabulary — against the real
#   producers, and goes red when a case pins a word the product no
#   longer says.
#
# So renaming `not-evaluable`, or dropping a key from the document, does
# not quietly leave a corpus describing a contract that no longer
# exists: it turns this red, in the same run that made the change.
#
# WHY IT DOES NOT RE-RUN THE COMMANDS. The honest version of «is this
# still true?» would execute `aegis check` against the live cluster, and
# no check in this verifier touches the cluster — they measure the
# ARTIFACT. Re-running also answers a different question (what does the
# world look like NOW) which is what `aegis console capture` is for. The
# vocabulary, on the other hand, is a fact of the source, and that is
# where it is read.
D125=""
CASES125="$AEGIS_ROOT/console/cases"
[[ -d "$CASES125" ]] || { skip "there is no corpus yet ($CASES125): this check has no subject"; return; }
find "$CASES125" -name case.yaml | grep -q . || { skip "the corpus has no case.yaml: nothing pins a vocabulary"; return; }

OUT125="$(python3 "$AEGIS_ROOT/verify/checks/125.py" "$AEGIS_ROOT" 2>&1)"
RC125=$?
if (( RC125 != 0 )); then
    fail "the reader of check 125 itself failed (rc $RC125) and no vocabulary was compared: $OUT125"
    return
fi
SCOPE125=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE125="${hit#SCOPE: }" ;;
        *)       D125="$D125 $hit;" ;;
    esac
done <<< "$OUT125"

printf '    %s\n' "${SCOPE125:-the scope was not reported}"
if [[ -n "$D125" ]]; then
    fail "the corpus pins a vocabulary the product no longer speaks:$D125"
else
    pass "every state word and every document key the corpus pins is one a producer still emits"
fi
}
