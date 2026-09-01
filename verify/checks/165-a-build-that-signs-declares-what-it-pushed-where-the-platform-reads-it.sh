# title: a build that signs declares what it pushed, in the form the platform reads
# origin: new in v3 — 2026-09-01, after two AI lanes stayed out of the audit trail
check() {
# `AEGIS_EVENT <json>` is not console decoration. Vector matches
# exactly that marker and routes those lines to vlogs-events with a
# year of retention, and the supply-chain dashboard reads them. It is
# the audit trail of everything this platform signs.
#
# Measured on 2026-09-01: the two AI lanes printed the same JSON
# WITHOUT the marker. The images built, scanned and signed fine, and
# their events reached nothing — no audit store, no dashboard panel.
# A hole that shows up as an absence, which is the kind nobody
# notices: the panel looked healthy because the builds it did know
# about were all there.
#
# The second half is the one that made the failure visible at all.
# Phase 87 has to pin the digest of what it just built, and to address
# it, it needs the tag. Each lane names tags its own way, so a phase
# that GUESSES the tag is a second place deciding it — and two places
# deciding the same thing drift. The phase reads the event instead,
# which is why the marker being absent stopped being merely invisible
# and started being fatal. Two properties, one contract:
#
#   1. every pipeline in the seed that SIGNS declares its event with
#      the marker the platform's own consumer matches (derived from
#      Vector's configuration, not typed here);
#   2. the phase that pins reads the tag from that event rather than
#      composing one.
V="$SEED/platform/k8s/base/observability/vector/values.yaml"
[[ -f "$V" ]] || { skip "there is no vector configuration in the seed: nothing consumes the events"; return; }

# the contract is DERIVED from its consumer
MARK="$(grep -oE 'AEGIS_EVENT ' "$V" | head -1)"
[[ -n "$MARK" ]] || { skip "vector no longer matches an event marker: the contract this check derives from is gone"; return; }

D165=""
SIGNERS=""
while IFS= read -r f; do
    case "$f" in *.md|*.yaml) continue ;; esac   # prose and policy, not pipelines
    SIGNERS="$SIGNERS $f"
    grep -qF "$MARK" "$f" \
      || D165="$D165 ${f#"$SEED"/} signs an image and never declares «${MARK% }»: what it pushed reaches neither the audit store nor the dashboard, and a phase that needs its tag cannot ask it;"
done < <(grep -rl 'cosign sign' "$SEED" 2>/dev/null | sort)

[[ -n "$SIGNERS" ]] || { skip "no pipeline in the seed signs images"; return; }

# (2) the phase pins what the build declared, it does not compose it
P87="$AEGIS_ROOT/init/phases/87-ai.sh"
if [[ -f "$P87" ]] && grep -q 'ai-image-pinned' "$P87"; then
    # the boundary matters: without it `jenkins_build_evento` — any
    # rename that keeps the prefix — reads as the real reader, and the
    # tooth for this very assertion goes green over a phase that calls
    # a function nobody defines.
    READER='jenkins_build_event($|[^A-Za-z0-9_])'
    if ! grep -qE "$READER" "$P87"; then
        D165="$D165 87-ai.sh pins AI images without reading the event the build declared: the tag is composed in a second place, and each lane names its tags differently;"
    elif ! grep -qE "^jenkins_build_event\(\)" "$AEGIS_ROOT/lib/jenkins.sh"; then
        D165="$D165 87-ai.sh calls a reader lib/jenkins.sh does not define: the phase would die at its first AI build, with set -u, on a name that does not exist;"
    fi
fi

printf '    %s signing pipelines · marker «%s» derived from vector\n' \
    "$(wc -w <<< "$SIGNERS")" "${MARK% }"
if [[ -n "$D165" ]]; then fail "something signs and does not say what it pushed:$D165"
else pass "every signing pipeline in the seed declares its supply-chain event with the marker the platform's consumer matches, and the phase that pins reads the tag from that event instead of composing one"; fi
}
