# title: webhooks: HMAC RE-SYNCED on existing hooks (run #10)
# origin: verify-static.sh (v2) ══ 31
check() {
# the skip on "already exists" left an old hook signing with an HMAC
# different from the store's → a permanent 400 on the redeliver
# (phase 35). GitHub NEVER returns config.secret → no comparison is
# possible; the fix is an unconditional PATCH. Structure demanded in
# the BODY of make_repo_webhook (non-comment lines): there is a `gh api
# -X PATCH ... hooks/` and no `return 0` happens BEFORE the first PATCH
# (the old shape of the bug: existence → return 0 without syncing):
WH_BODY="$(body_of make_repo_webhook "$PHASES/15-third-parties.sh" \
    | nc)"
PATCH_LN="$(echo "$WH_BODY" | grep -n -- '-X PATCH' | grep 'hooks/' | head -n1 | cut -d: -f1)"
RET0_LN="$(echo "$WH_BODY" | grep -n 'return 0' | head -n1 | cut -d: -f1)"
if [[ -z "$PATCH_LN" ]]; then
    fail "make_repo_webhook WITHOUT gh api -X PATCH over hooks/ (an existing hook keeps the old HMAC → 400)"
elif [[ -n "$RET0_LN" && "$RET0_LN" -lt "$PATCH_LN" ]]; then
    fail "make_repo_webhook has a return 0 BEFORE the PATCH (skip without re-syncing — the shape of bug #10)"
else
    pass "make_repo_webhook re-syncs the HMAC of existing hooks (PATCH before any return 0)"
fi
}
