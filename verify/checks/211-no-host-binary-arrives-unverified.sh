# title: no binary of the host is installed without proving its bytes, and no `curl | bash` is left
# origin: new in v3 — 2026-09-18, phase 05 admitted it in writing and helm ran a script off a moving branch (plan/17)
check() {
# HTTPS PROVES THE SERVER, NOT THE BYTES.
#
# Until 2026-09-18 every binary of the host arrived over https and was
# installed exactly as it came down: a cache, a mirror, a release
# re-cut under the same tag or a truncated transfer all passed. helm
# was the worst of the five — `curl | bash` of get-helm-3 taken from
# the MAIN branch of its own repo, which is not even a pinned script,
# handed a shell and root on the machine that holds every key of the
# instance. The phase itself said so in a comment: «per-artifact sha256
# checksums: deferred».
#
# The rule this fixes in place has two halves, and the second is the
# one that rots quietly: a tool that gets its own download branch has
# to verify what it downloaded, AND a tool that has no branch has to be
# pinned `apt`, because apt installs the line's current version and any
# number written beside it in group_vars would be a promise nobody
# keeps. That second half is what `aegis update` trips over: it would
# read the number, measure it against upstream and propose a bump the
# phase has no way to install.
D211=""
PH211="$AEGIS_ROOT/init/phases/05-host.sh"
[[ -f "$PH211" ]] || { skip "there is no phase 05: no host userland is installed here"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/211.py" ]] || { fail "check 211 has no sidecar: the tools and their pins were never paired"; return; }

# (a) a pipe into a shell, anywhere in the init. It is grepped over
#     CODE and not prose (the comments above deliberately spell the
#     pattern out; check 168's lesson is that a check which reads
#     comments as code goes red for a sentence).
PIPED211="$(nc "$AEGIS_ROOT"/init/phases/*.sh "$AEGIS_ROOT"/lib/*.sh 2>/dev/null \
    | grep -nE 'curl[^|]*\|[^|]*(ba)?sh( |$)' || true)"
[[ -z "$PIPED211" ]] || D211="$D211 something still pipes a download into a shell: ${PIPED211//$'\n'/ };"

# (b) every branch that downloads, verifies; every tool without a
#     branch is pinned apt. Both derived by the sidecar from the phase
#     and from group_vars, with no list written down here.
OUT211="$(python3 "$AEGIS_ROOT/verify/checks/211.py" "$AEGIS_ROOT" 2>&1)"
RC211=$?
if (( RC211 != 0 )); then
    fail "the exercise of check 211 itself failed (rc $RC211): $OUT211"
    return
fi
SCOPE211=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE211="${hit#SCOPE: }" ;;
        *)       D211="$D211 $hit;" ;;
    esac
done <<< "$OUT211"

printf '    %s\n' "${SCOPE211:-the scope was not reported}"
if [[ -n "$D211" ]]; then
    fail "a binary of the host can arrive without its bytes being proved:$D211"
else
    pass "every download of the host verifies its published checksum, every other tool is pinned apt, and nothing pipes a download into a shell ($SCOPE211)"
fi
}
