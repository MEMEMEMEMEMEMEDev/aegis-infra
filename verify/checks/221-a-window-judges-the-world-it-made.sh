# title: a window judges the world it actually made, not one the page or a rolling cluster produced
# origin: new in v3 — 2026-09-20, a window called its own maintenance page damage, and a rollback that reverted nothing
check() {
# THREE MISTAKES, ALL FOUND BY RUNNING ONE, AND ALL THE SAME MISTAKE:
# comparing against a world that is not the one the window is
# responsible for.
#
#   · IT JUDGED WITH THE PAGE UP. The round measures the tenant sites
#     through the edge; the page lives at the edge. Compared against the
#     photo, the page doing its job reads as damage the window caused.
#     The acceptance under the page belongs against a round taken WITH
#     the page up and nothing else changed yet.
#   · IT JUDGED BEFORE THE CLUSTER SETTLED. A sync is a request, not an
#     arrival. Bumping busybox and curl rolls half the platform, and a
#     Jenkins that is restarting has «no build at all» on fourteen jobs.
#     The window called that damage; it healed in four minutes.
#   · AND THE ROLLBACK DID NOT ROLL BACK. A window ends red in two ways
#     —a layer's acceptance and the global one— and only the first ever
#     reverted. The second set the word «rolled-back» on a window that
#     kept every commit it had made. The name of a thing is not the
#     thing.
D221=""
[[ -f "$LIBEXEC/aegis-update" ]] || { skip "there is no aegis update"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/221.py" ]] || { fail "check 221 has no sidecar"; return; }

OUT221="$(python3 "$AEGIS_ROOT/verify/checks/221.py" "$AEGIS_ROOT" 2>&1)"
RC221=$?
if (( RC221 != 0 )); then
    fail "the exercise of check 221 itself failed (rc $RC221): $OUT221"
    return
fi
SCOPE221=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE221="${hit#SCOPE: }" ;;
        *)       D221="$D221 $hit;" ;;
    esac
done <<< "$OUT221"

printf '    %s\n' "${SCOPE221:-the scope was not reported}"
if [[ -n "$D221" ]]; then
    fail "a window can judge a world it did not make:$D221"
else
    pass "the acceptance is measured against a baseline taken under the page, every sync is waited on, and both red endings go through the one way back ($SCOPE221)"
fi
}
