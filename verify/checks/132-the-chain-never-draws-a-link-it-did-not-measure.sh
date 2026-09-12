# title: the chain of a push never draws a link nobody measured
# origin: new in v3 — 2026-09-12, `aegis builds` is the panel that shows scan and signature (plan/11 §A5)
check() {
# THIS IS THE PANEL THAT SELLS THE PRODUCT, which is exactly why it is
# the one that must not lie. Every hosting platform draws deployments.
# What none of them draws is the two links in the middle — whether
# anybody SCANNED the image and whether anybody SIGNED it — and aegis
# does both on every push.
#
# THE DRIFT THAT WOULD NOT FAIL. The command decides whether an image
# was scanned by reading `scan_skipped` off the pipeline's event. Rename
# that field in Jenkinsfile.app and the reader gets nothing; nothing is
# not «true»; and the link is drawn as DONE. An image nobody scanned
# would carry a green tick — the exact inversion of what this panel
# exists to prove, caused by a rename nobody would think twice about,
# with neither file mentioning the other. So the fields are DERIVED from
# the pipeline's own event and compared.
#
# And two refusals, both exercised by calling the real function:
#   · a build the anti-loop skipped is not «done» on any link. Nothing
#     was built, so nothing was scanned or signed.
#   · the links this source cannot see —ArgoCD's sync, the cluster's
#     admission— are reported as NOT EVALUATED, by name. Omitting them
#     would let somebody count four ticks and believe the deploy
#     arrived, which is precisely the question they were debugging.
D132=""
[[ -f "$LIBEXEC/aegis-builds" ]] || { skip "there is no builds command yet: no chain is drawn"; return; }

OUT132="$(python3 "$AEGIS_ROOT/verify/checks/132.py" "$AEGIS_ROOT" 2>&1)"
RC132=$?
if (( RC132 != 0 )); then
    fail "the exercise of check 132 itself failed (rc $RC132) and the chain was never measured: $OUT132"
    return
fi
SCOPE132=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE132="${hit#SCOPE: }" ;;
        *)       D132="$D132 $hit;" ;;
    esac
done <<< "$OUT132"

printf '    %s\n' "${SCOPE132:-the scope was not reported}"
if [[ -n "$D132" ]]; then
    fail "the chain draws a link nobody measured:$D132"
else
    pass "every field it reads is one the pipeline writes, a skipped build ticks nothing, and the two links beyond this source are named as unmeasured ($SCOPE132)"
fi
}
