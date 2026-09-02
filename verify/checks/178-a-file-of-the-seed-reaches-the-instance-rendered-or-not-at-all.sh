# title: a file of the seed reaches the instance rendered, or it does not reach it
# origin: new in v3 — 2026-09-01 at night, measured while carrying a fix by hand
check() {
# The seed ships its files WITH placeholders; the instance has them
# RESOLVED. That asymmetry is by design, and it means a plain copy from
# one tree to the other is not a copy: it is an un-render.
#
# Measured on the night of 2026-09-01, carrying a real fix over:
# copying seed/platform/k8s/base/platform/jenkins-secrets/bundle.yaml
# onto the instance's copy put __ROOT_DOMAIN__ back into Jenkins's
# route, and jenkins.<domain> stopped routing through Traefik. Nothing
# failed while copying. The file was simply un-rendered, and the
# platform said so hours later, through a route that no longer existed.
#
# The advice seed_drift_report printed until that night was exactly
# that copy — so the tool that exists to keep a fix from getting lost
# was handing out the way to break the instance instead.
#
# Two things are demanded here, and the second is the one that bit:
#   1. no path of the artifact copies a file of the seed into the
#      instance without rendering it afterwards. The single exception
#      is legitimate on its own terms and is not written down as a
#      name: the birth copy REFUSES to write onto a tree that already
#      has a history (platform/.git), so it never lands on a rendered
#      file.
#   2. the advice the drift report prints names the path that renders
#      — and the name is DERIVED from the code, not typed here.
D178=""
# The scan is python, in its own file, and a scan that dies takes this
# check with it (the lesson check 166 paid for: a sed that printed
# nothing gave ALL PASS over a broken file). It drops comments AND
# lines that only print, because here BOTH traps are present at once:
# the helper under test PRINTS a `cp` on purpose, and the paragraph
# above it explains why that `cp` is wrong.
if ! OUT="$(python3 "$AEGIS_ROOT/verify/checks/178.py" "$AEGIS_ROOT" 2>/dev/null)"; then
    D178="$D178 the scan itself failed and this check measured nothing;"
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D178="$D178 $hit;"
    done <<< "$OUT"
fi
N="$(python3 "$AEGIS_ROOT/verify/checks/178.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"

printf '    %s places in the artifact copy something of the seed into the instance\n' "${N:-0}"
if [[ -n "$D178" ]]; then fail "a file of the seed can reach the instance un-rendered:$D178"
else pass "every copy from the seed into the instance renders afterwards or refuses to touch a tree with a history, and the drift report advises the path that renders"; fi
}
