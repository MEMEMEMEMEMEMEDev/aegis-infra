# title: the app scan honors a repo-local trivyignore, guarded and without softening the bar
# origin: new in v3 — 2026-09-04, the shop's worker: a base-layer CVE the platform already accepted reappeared in the app scan
check() {
# MEASURED 2026-09-04. The shop's worker runs on python:3.12-slim, a base
# the platform MIRRORS and whose one open CVE (CVE-2026-14456, an OpenSSL
# QUIC-server DoS) it already accepted, dated, in mirror-images'
# trivyignore. The app image contains that same libssl layer, so the app
# scan —which until now used NO ignorefile, on the principle «our own
# code has no exceptions»— flagged it again and refused to build. The
# principle is right and stays: the fix is not «apps may ignore their own
# CVEs», it is «the app scan honors a repo-local trivyignore.yaml for the
# base-layer exceptions the platform already vets», and only in a
# disciplined shape:
#
#   1. it reaches trivy — the file is passed with --ignorefile, not just
#      present in the repo doing nothing;
#   2. it is GUARDED by `[ -f trivyignore.yaml ]` — an app that ships
#      none (the normal case) is still scanned with no exceptions;
#   3. it does not SOFTEN the scan — CRITICAL,HIGH and --ignore-unfixed
#      stay, so the ignorefile carries a named base CVE and is not a way
#      to lower the bar for everything.
#
# check 136 already requires every entry in such a file to carry an
# expired_at, so an undated ignore is refused there; here the concern is
# that the pipeline actually consults it, safely.
D189=""
TPL="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
[[ -f "$TPL" ]] || { skip "the seed ships no Jenkinsfile.app: this check has no subject"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/189.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 189 itself failed (rc $RC) and this check measured nothing about the scan stage"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D189="$D189 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/189.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"
printf '    %s facts asked of the scan stage, with the prose around it stripped\n' "${N:-0}"
if [[ -n "$D189" ]]; then fail "the app scan does not honor a repo-local trivyignore in the disciplined shape:$D189"
else pass "the app scan passes --ignorefile trivyignore.yaml when the repo ships one, guarded by its existence, and without softening CRITICAL,HIGH or --ignore-unfixed"; fi
}
