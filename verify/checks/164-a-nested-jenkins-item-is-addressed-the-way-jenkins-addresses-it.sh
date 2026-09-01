# title: a nested Jenkins item is addressed the way Jenkins addresses it
# origin: new in v3 — 2026-09-01, after a 404 was reported as a missing job
check() {
# Jenkins nests items by REPEATING /job/: the main branch of the
# multibranch ai-gateway-mb lives at /job/ai-gateway-mb/job/main. Write
# /job/ai-gateway-mb/main and the answer is a 404 — which the caller
# then reports as «the API is down or the job does not exist», about a
# job that is there with its branch indexed. Measured on 2026-09-01:
# phase 87 died twice on that, and the comment directly above the
# offending line already said the branch is the buildable item. The
# idea was right; writing the path by hand is what failed.
#
# So the rule is not «call sites must remember the /job/ in the
# middle»: five of them remembered and the sixth did not, which is what
# a rule enforced by memory always looks like. The rule is that the
# LIBRARY builds the URL, and it is checked in the two ways it can
# break:
#
#   1. STRUCTURE — no URL in lib/jenkins.sh interpolates a raw item
#      name. One forgotten interpolation is one silent 404, and there
#      were eleven of them to convert.
#   2. BEHAVIOUR — the translation is run, right here, over the three
#      shapes the artifact actually hands it. Structure alone would
#      accept a _jenkins_job that exists and returns its argument.
J="$AEGIS_ROOT/lib/jenkins.sh"
[[ -f "$J" ]] || { fail "there is no lib/jenkins.sh: $J"; return; }

D164=""

# (1) structure: nothing builds a path out of a raw name
RAW="$(grep -nE '/job/\$[A-Za-z0-9_{]' "$J" \
       | grep -v '_jenkins_job' \
       | sed -E 's/^([0-9]+):[[:space:]]*//' \
       | grep -vE '^#' || true)"
[[ -z "$RAW" ]] || D164="$D164 lib/jenkins.sh builds a URL out of a raw item name — $(printf '%s' "$RAW" | head -2 | paste -sd' | ') — and a name with a nesting level in it lands on a 404 that gets reported as a missing job;"

# (2) behaviour: the three shapes the artifact hands it
if ! grep -q '_jenkins_job()' "$J"; then
    D164="$D164 lib/jenkins.sh does not translate item names at all: every call site is back to writing the nesting by hand, which is the arrangement that failed;"
else
    OUT="$(bash -c '
        source "$1" 2>/dev/null || exit 3
        printf "%s|%s|%s" \
            "$(_jenkins_job "ai-gateway-mb/main")" \
            "$(_jenkins_job "ai-gateway-mb/job/main")" \
            "$(_jenkins_job "ci-images")"
    ' _ "$J" 2>/dev/null)" || OUT="(it could not be sourced)"
    WANT="ai-gateway-mb/job/main|ai-gateway-mb/job/main|ci-images"
    [[ "$OUT" == "$WANT" ]] || \
        D164="$D164 the translation does not produce what Jenkins addresses: got «$OUT», expected «$WANT» (the second case is the one that matters most — a path already correct must survive it unchanged, or the five call sites that were right break the day this lands);"
fi

printf '    %s call sites hand this library an item name\n' \
    "$(grep -rhoE 'jenkins_(build_retry|fire|wait_build|next_build)\b' \
        "$AEGIS_ROOT/init/phases/" "$AEGIS_ROOT/libexec/" 2>/dev/null | wc -l)"
if [[ -n "$D164" ]]; then fail "a nested Jenkins item is addressed by hand:$D164"
else pass "the library translates every item name into the path Jenkins addresses, no URL is built from a raw name, and a path that was already correct survives the translation unchanged"; fi
}
