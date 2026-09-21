# title: a change in the seed can reach a living instance, and the way over never takes what is the instance's: its pins, its derived blocks, its contracts
# origin: new in v3 — 2026-09-01 a fix in the seed never reached the instance (three times); 2026-09-20 the house instance carried 32 alert rules while the seed shipped 41
check() {
# A FIX IN THE PRODUCT NEVER REACHED A LIVE INSTANCE, and said nothing
# while not reaching it. seed_drift_report named the drift and seed_fetch
# copied one file with its render; nothing put the two together as a
# verb, and nothing knew that a seed file can carry what the INSTANCE
# moved: a chart version the update window bumped, the kaniko tag, a
# derived block of tenant jobs. A bare copy would have brought the seed's
# structure AND its older versions — a downgrade dressed as a fix.
# `aegis seed diff` classifies every file the seed ships: the instance's
# (never brought over), the mixed ones the phases append to (read by
# eye), the ones that differ only in pins (the window's), the ones the
# seed added, the ones it changed. `aegis seed apply` copies and renders,
# splices the instance's derived block back and writes its pins back
# through the same edit the window uses. This check drives all of that
# over a scratch pair of trees, with no instance and no cluster.
D225=""
[[ -f "$LIBEXEC/aegis-seed" ]] || { fail "there is no aegis seed: a fix in the seed has no way into a living instance"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/225.py" ]] || { fail "check 225 has no sidecar"; return; }

OUT225="$(python3 "$AEGIS_ROOT/verify/checks/225.py" "$AEGIS_ROOT" 2>&1)"
RC225=$?
if (( RC225 != 0 )); then
    fail "the exercise of check 225 itself failed (rc $RC225): $OUT225"
    return
fi
SCOPE225=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE225="${hit#SCOPE: }" ;;
        *)       D225="$D225 $hit;" ;;
    esac
done <<< "$OUT225"

printf '    %s\n' "${SCOPE225:-the scope was not reported}"
if [[ -n "$D225" ]]; then
    fail "a seed change can still miss an instance, or take what is hers:$D225"
else
    pass "aegis seed tells the instance's files, the mixed ones, the pins and the real changes apart, refuses what is the instance's, and brings a file over with her pins and derived blocks kept ($SCOPE225)"
fi
}
