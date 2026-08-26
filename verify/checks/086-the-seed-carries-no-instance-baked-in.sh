# title: the seed carries NO instance baked inside it
# origin: verify-static.sh (v2) ══ 86
check() {
# The structural risk of syncing the seed from the instance: the live
# tree has its placeholders ALREADY RESOLVED (phase 10 renders them in
# place), so copying without un-rendering puts ONE instance's values
# inside the product. The failure does not show up here: it shows up on
# the next startup, on another machine, against a repo that does not
# exist.
#
# It already happened: until 2026-08-11 the seed's org-canary/bundle.yaml
# pointed at git@github.com:<a real owner>/<a real repo>.git. An
# instance born from that seed cloned ANOTHER owner's canary.
#
# The check measures by SHAPE, not against aegis-init.conf, because that
# file is in .gitignore and does not exist in a clean clone: a check
# that depended on it would go green by absence, which is exactly the
# signal that cannot tell "there is no leak" from "I did not look".
# Shape is enough: generated material (age/PEM) has no legitimate reason
# to be in the artifact, and every GitHub repo in the artifact is
# referenced through __GH_OWNER__.
D86=""
# 1) generated-class material (owners: phases 10 and 80). In the seed
#    they go as __AGE_PUBLIC__ / __COSIGN_PUB__ / __AEGIS_CA_PEM__.
LEAK_GEN="$(grep -rlE 'age1[0-9a-z]{20,}|-----BEGIN (CERTIFICATE|PUBLIC KEY|EC PRIVATE KEY)-----' \
            "$P" 2>/dev/null || true)"
[[ -n "$LEAK_GEN" ]] && D86="$D86 generated material (age/PEM) versioned in the seed: $(echo "$LEAK_GEN" | tr '\n' ' ');"
# 2) every GitHub repo owner in the artifact is the placeholder. docs/
#    is excluded: the prose names the repos by default on purpose. The
#    pattern demands REPO shape (scheme + owner + name): without the
#    trailing `/repo` this very check read `https://api.github.com/meta`
#    —an API endpoint, inside a comment— as if it were an owner.
OWNERS="$(grep -rhoE '(git@|https://)github\.com[:/][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$P" \
          --include='*.yaml' --include='*.yml' --include='*.tf' \
          --include='*.tpl' --include='*.j2' --include='*.sh' 2>/dev/null \
          | sed -E 's|.*github\.com[:/]||; s|/.*||' | sort -u | grep -v '^__GH_OWNER__$' || true)"
[[ -n "$OWNERS" ]] && D86="$D86 literal GitHub repo owner in manifests (should be __GH_OWNER__): $(echo "$OWNERS" | tr '\n' ' ');"
# 3) reinforcement when there IS a local config: the values that
#    distinguish this instance are the ones that DIFFER from the
#    .example's default — one equal to the default identifies nobody and
#    is not a leak.
# The INSTANCE's conf (02 §1): in v2 it lived inside the product and
# this comparison worked on its own. With the product/instance split it
# has to be gone looking for — otherwise the strongest sub-check
# (contrasting this machine's REAL values against the artifact) switched
# itself off and the check passed «by shape» without saying it had lost
# half of its reach. Its tooth revealed it.
CONF86="${AEGIS_CONF:-${AEGIS_HOME:-$HOME/aegis}/aegis.conf}"
if [[ -f "$CONF86" ]]; then
    N86=0
    for k in GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN REGISTRY_CLUSTER_IP ACME_EMAIL; do
        live="$(grep -E "^\s*$k=" "$CONF86" | head -1 | sed -E 's/^[^=]+=\s*"?([^"#]*[^"# ])"?.*/\1/')"
        example="$(grep -E "^\s*$k=" "$AEGIS_ROOT/init/aegis-init.conf.example" | head -1 | sed -E 's/^[^=]+=\s*"?([^"#]*[^"# ])"?.*/\1/')"
        [[ -z "$live" || "$live" == "$example" ]] && continue
        N86=$((N86+1))
        HIT="$(grep -rl -- "$live" "$P" 2>/dev/null || true)"
        [[ -n "$HIT" ]] && D86="$D86 THIS instance's value for $k appears in: $(echo "$HIT" | tr '\n' ' ');"
    done
    EXTRA86="+ $N86 own values contrasted against the .example"
else
    EXTRA86="(without $CONF86: only the contrast by shape)"
fi
if [[ -n "$D86" ]]; then fail "the seed has an instance inside it:$D86"
else pass "the seed bakes in no instance: no versioned age/PEM, every repo through __GH_OWNER__ $EXTRA86"; fi
}
