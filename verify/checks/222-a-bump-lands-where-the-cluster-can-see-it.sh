# title: a bump that only reached git is not a bump: the layer syncs whoever applies the file, and then asks the cluster what is running
# origin: new in v3 — 2026-09-20, six charts committed, pushed, synced, accepted rc 0, and every one still running its old version
check() {
# THE QUIETEST FAILURE THIS PROTOCOL HAS PRODUCED. A chart's
# `targetRevision` does not live in what the app deploys; it lives in
# the Application OBJECT, and that object is applied by the App-of-Apps,
# which has no automated policy on purpose —nothing retargets an
# Application without a person. So the layer edited git, pushed, synced
# the app, and the app dutifully reconverged against the version the
# object still named. Synced. Healthy. The round agreed, because the
# round asks the instance and the instance had not changed. Six charts
# reported raised; six charts still on their old versions afterwards.
#
# Two things stop it, and this check demands both: sync whoever APPLIES
# the file that was edited, and then ask the CLUSTER which version is
# running instead of assuming the commit answered.
D222=""
[[ -f "$LIBEXEC/aegis-update" ]] || { skip "there is no aegis update"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/222.py" ]] || { fail "check 222 has no sidecar"; return; }

OUT222="$(python3 "$AEGIS_ROOT/verify/checks/222.py" "$AEGIS_ROOT" 2>&1)"
RC222=$?
if (( RC222 != 0 )); then
    fail "the exercise of check 222 itself failed (rc $RC222): $OUT222"
    return
fi
SCOPE222=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE222="${hit#SCOPE: }" ;;
        *)       D222="$D222 $hit;" ;;
    esac
done <<< "$OUT222"

printf '    %s\n' "${SCOPE222:-the scope was not reported}"
if [[ -n "$D222" ]]; then
    fail "a bump can be reported raised without reaching the cluster:$D222"
else
    pass "the file's applier is synced before the app, and the version the layer wrote is read back off the live Application ($SCOPE222)"
fi
}
