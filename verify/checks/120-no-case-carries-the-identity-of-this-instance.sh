# title: no case of the console carries a value that identifies this instance
# origin: new in v3 — 2026-09-11, the corpus (plan/15) is the first thing of the INSTANCE that travels to the public repo
check() {
# WHAT IS NEW HERE, and why it needed its own guard.
#
# Until the corpus existed, nothing of this machine travelled to the
# product: the seed carries placeholders and check 086 makes sure of
# it. The cases break that for the first time — they are, on purpose,
# the real documents this instance emitted, and `aegis-infra` is a
# PUBLIC repository. A capture that forgets to scrub is not a bug that
# fails: it is a domain, an email or a cloudflare account id sitting in
# a git history where it cannot be taken back.
#
# The derivation is 086's, and it is derived rather than listed for the
# same reason: a roster of «secrets to scrub» goes stale the day
# somebody adds a key, and the miss is invisible.
#   · only values that DIFFER from aegis-init.conf.example — a value
#     equal to the default identifies nobody;
#   · minus the ones that are already words of the product's own source.
#     `AI=gpu` and `KUBE_CONTEXT_EXPECTED=default` differ from the
#     example and name nobody; masking them would mangle every document
#     that says «gpu» for an unrelated reason, and a corpus nobody can
#     read stops being read.
#   · plus $HOME, which is always identifying and lives in no conf.
#     Measured the first time a case was captured: the capture guarded
#     the documents and nobody guarded the sentence beside them, so the
#     reason a command gave for having no document carried an absolute
#     path with the operator's username.
#
# AND THE SCOPE IS SAID OUT LOUD. On a clean clone there is no
# aegis.conf and only $HOME can be contrasted. That is half the check,
# so it prints what it could reach — a green that hides a scope is the
# disease this repo treats everywhere else.
D120=""
CASES120="$AEGIS_ROOT/console/cases"
[[ -d "$CASES120" ]] || { skip "there is no corpus yet ($CASES120): nothing of this instance travels"; return; }

OUT120="$(python3 "$AEGIS_ROOT/verify/checks/120.py" "$AEGIS_ROOT" 2>&1)"
RC120=$?
if (( RC120 != 0 )); then
    fail "the sweep of check 120 itself failed (rc $RC120) and nothing was measured about what the corpus carries: $OUT120"
    return
fi
SCOPE120=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE120="${hit#SCOPE: }" ;;
        *)       D120="$D120 $hit;" ;;
    esac
done <<< "$OUT120"

printf '    %s\n' "${SCOPE120:-the scope was not reported}"
if [[ -n "$D120" ]]; then
    fail "the corpus carries the identity of this instance:$D120"
else
    pass "no case carries a value of this instance's conf nor the operator's home ($SCOPE120)"
fi
}
