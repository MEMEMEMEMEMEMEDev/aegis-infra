# title: the transient-network list speaks every language the seed downloads in
# origin: new in v3 — 2026-09-01, after a four-hour build was not retried
check() {
# `AEGIS_NET_SIGS` is the one place that decides whether a failure is
# the network having a bad moment or the artifact being wrong. Three
# things consume it: argo_sync re-fires, argo_secrets_gate waits, and
# jenkins_build_retry re-fires the build.
#
# Every signature in it was written from what GO and GIT say, because
# those were the only things downloading when it was written. On
# 2026-09-01 the longest build in the product — pip pulling multi-GB
# wheels for the GPU engine — hit a read timeout against
# files.pythonhosted.org, and the retry answered «FAILURE with NO
# network signature: a real failure, it is not retried». A hiccup
# stopped a four-hour build and reported it as a defect, which is the
# exact thing this list exists to prevent.
#
# So the property is not «the list is long». It is that the list
# speaks the language of every tool the seed actually downloads with,
# and the set of those tools is DERIVED from the Containerfiles rather
# than remembered — that is how pip got missed.
D169=""
# The list is read from the ARTIFACT, not from the environment: this
# check measures what lib/common.sh ships, which is what a fresh
# instance will run.
SIGS="$(sed -n "s/^AEGIS_NET_SIGS='\\(.*\\)'$/\\1/p" "$AEGIS_ROOT/lib/common.sh")"
[[ -n "$SIGS" ]] || { fail "lib/common.sh no longer defines AEGIS_NET_SIGS: the one place that tells a network hiccup from a defect is gone"; return; }
if ! OUT="$(SIGS="$SIGS" python3 "$AEGIS_ROOT/verify/checks/169.py" "$SEED" 2>/dev/null)"; then
    D169="$D169 the scan itself failed and this check measured nothing;"
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D169="$D169 $hit;"
    done <<< "$OUT"
fi
USED="$(SIGS="$SIGS" python3 "$AEGIS_ROOT/verify/checks/169.py" "$SEED" 2>&1 >/dev/null | awk '/__USED__/{$1=""; print}')"

printf '    the seed downloads with:%s\n' "$USED"
if [[ -n "$D169" ]]; then fail "a transient network fault would read as a defect:$D169"
else pass "the transient-network list knows a word of every tool the seed downloads with, so a timeout in any of them is retried instead of being reported as a defect"; fi
}
