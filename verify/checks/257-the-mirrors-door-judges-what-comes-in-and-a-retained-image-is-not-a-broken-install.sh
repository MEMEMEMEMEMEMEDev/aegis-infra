# title: the mirror's door judges each new image with the one verdict, does not judge again what came in from the same source, and a retained image stops the install only if the platform runs it
# origin: new in v3 — 2026-09-30, the Arch lab VM, phase 80: python:3.12-slim and nodejs-distroless:22 (two OpenSSL CVEs of the day before, runtimes the platform does not use) killed a clean install; plan/21 stage 4
check() {
# mirror-images re-judged every entry on every run with a binary scan,
# and phase 80 died on anything red. The sidecar reads the job's scan,
# provenance and ending as code, lib/jenkins.sh's UNSTABLE, and RUNS
# phase 80's door with a simulated Jenkins.
D257=""
[[ -f "$AEGIS_ROOT/verify/checks/257.py" ]] || { fail "check 257 has no sidecar"; return; }
OUT257="$(python3 "$AEGIS_ROOT/verify/checks/257.py" "$AEGIS_ROOT" 2>&1)"
RC257=$?
(( RC257 == 0 )) || { fail "the exercise of check 257 itself failed (rc $RC257): ${OUT257:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE257="${hit#SCOPE: }" ;;
        *)       D257="$D257 $hit;" ;;
    esac
done <<< "$OUT257"
printf '    %s\n' "${SCOPE257:-the scope was not reported}"
if [[ -n "$D257" ]]; then
    fail "the mirror's door does not judge what the policy says:$D257"
else
    pass "a new image is judged by the verdict (debt enters, retained is named and not pushed, unjudged is broken), what came in from the same source is not judged again, UNSTABLE is rc 4 and not re-fired, and phase 80 stops only for an image the platform runs (${SCOPE257})"
fi
}
