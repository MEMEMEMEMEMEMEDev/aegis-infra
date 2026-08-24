# title: phases that mutate the platform repo SYNC first (CR-6 in-VM)
# origin: verify-static.sh (v2) ══ 52
check() {
# Disease D (dual git state): a manual fix on GitHub during a resume
# leaves the local clone behind and the next push overwrites/collides.
D52=""
PRS_BODY="$(body_of platform_repo_sync "$LIBS/common.sh")"
[[ -n "$PRS_BODY" ]] || D52="$D52 platform_repo_sync missing from common.sh;"
echo "$PRS_BODY" | grep -q -- '--ff-only' \
    || D52="$D52 the sync is not ff-only (an automatic merge would decide on its own);"
echo "$PRS_BODY" | grep -q 'DIVERGED' \
    || D52="$D52 no explicit death on divergence;"
# EVERY phase that mutates the repo (git -C "$PLATFORM_DIR" on a
# non-comment line) must call the sync — dynamic, covers future phases:
for ph in "$AEGIS_ROOT"/init/phases/*.sh; do
    PH_NC="$(nc "$ph")"
    if echo "$PH_NC" | grep -q 'git -C "\$PLATFORM_DIR"'; then
        # phase 12 SEEDS the repo (it creates the remote, a deliberate
        # push --force) — the sync does not apply to the birth:
        [[ "$(basename "$ph")" == 12-* ]] && continue
        echo "$PH_NC" | grep -q '^platform_repo_sync$' \
            || D52="$D52 $(basename "$ph") mutates the repo without platform_repo_sync;"
    fi
done
if [[ -n "$D52" ]]; then fail "dual git state:$D52"
else pass "every phase that mutates platform syncs first (ff-only, divergence = stop)"; fi
}
