# title: no init probe measures Cloudflare's edge believing it measures the cluster (#87)
# origin: verify-static.sh (v2) ══ 90
check() {
# The defect this check exists to prevent, measured on 2026-08-13:
# ever since Access sits in front of argocd.<dom> and jenkins.<dom>
# (#76), a bare curl to those hostnames receives a 302 served by
# CLOUDFLARE — it does not enter the tunnel, does not touch traefik,
# does not see the app. Phase 35's "edge-responde" gate accepted
# `30[12]`, so it passed green with the whole cluster switched off.
#
# The list of protected hostnames is DERIVED from the tofu module, it
# is not baked in here: the day somebody puts a third hostname behind
# Access, this check covers it on its own. Baking it in would be C15 —
# a check tied to a list lies as soon as the list changes.
D90=""
# It used to come from $ROOT/platform — the INSTANCE. See check 26's
# note: with product and instance in the same folder the wrong path
# gave the same result. The artifact is the SEED.
ACCESS_MOD="$P/tofu/modules/cloudflare-access"
if [[ ! -f "$ACCESS_MOD/main.tf" ]]; then
    D90="$D90 the cloudflare-access module does not exist: could not derive which hostnames are protected;"
else
    # prefixes of the applications' `domain`: "argocd.${var...}". From
    # ALL the module's .tf files and not only main.tf: HCL merges the
    # directory, and an application in its own file (grafana.tf, phase-85
    # §5) would fall outside the list with its hostname ALREADY
    # protected — a probe curling it bare would pass green. (The finding
    # noted in phase-85 §5 was WELL FOUNDED: this read only main.tf until
    # 2026-08-20.)
    PROTECTED="$(grep -hoE '^\s*domain\s*=\s*"[a-z0-9-]+\.\$\{var\.root_domain\}' "$ACCESS_MOD"/*.tf \
                  | sed -E 's/.*"([a-z0-9-]+)\..*/\1/' | sort -u)"
    [[ -n "$PROTECTED" ]] \
        || D90="$D90 the Access module declares no recognizable domain (did the shape change?);"
    for PHASE in "$PHASES"/*.sh; do
        # continuations are joined and comments discarded: the defect
        # lives in the code, and an example inside a comment is not a
        # defect (H4/check 41 — never grep a bare name).
        BODY="$(joincont "$PHASE" | nc)"
        for H in $PROTECTED; do
            # lines that curl THAT hostname without going through the helper:
            BAD="$(printf '%s\n' "$BODY" \
                     | grep -E "curl[^|]*https://$H\.\\\$(\{)?ROOT_DOMAIN" \
                     | grep -v 'edge_origin_responds' || true)"
            # CORRECTED on 2026-08-24. This `grep -v` is the anchor that
            # EXCLUDES the phases that already comply, so when the helper
            # was renamed edge_origin_responds -> edge_origin_responds it
            # did not go blind: it went FALSE RED, reporting perfectly
            # correct phases. A check that breaks toward red costs more
            # than one that breaks toward green — it sends someone to fix
            # something that is not broken, and the next time it cries
            # nobody comes. Check 111's ratchet caught it.
            [[ -z "$BAD" ]] \
                || D90="$D90 $(basename "$PHASE") curls $H.\$ROOT_DOMAIN without edge_origin_responds (under Access that measures CF's edge);"
        done
    done
    # and the helper has to really tell them apart: if it does not look
    # at where it redirects to, it is a curl by another name.
    grep -q 'cloudflareaccess\.com' "$LIBS/access.sh" 2>/dev/null \
        || D90="$D90 edge_origin_responds does not distinguish the redirect to cloudflareaccess.com — it does not separate «Access intercepted» from «the origin answered»;"
fi
if [[ -n "$D90" ]]; then fail "probes under Access:$D90"
else pass "init's probes against the $(printf '%s' "$PROTECTED" | wc -w) hostnames behind Access go through edge_origin_responds, which separates origin from edge"; fi
}
