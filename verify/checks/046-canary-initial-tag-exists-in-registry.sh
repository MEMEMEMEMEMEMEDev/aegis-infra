# title: the canary's initial tag = the one that EXISTS in the registry (H1 #13)
# origin: verify-static.sh (v2) ══ 46
check() {
F70_NC="$(nc "$PHASES/70-deploy-auto.sh")"
if echo "$F70_NC" | grep -q 'tags/list' \
   && echo "$F70_NC" | grep -q 'tag-real-en-registry' \
   && echo "$F70_NC" | grep -q 'newTag: main-'; then
    pass "phase 70 derives the tag from the registry (gate) and aligns the newTag before the deploy"
else
    fail "the initial tag still assumes the number of build #1 (cosmetic ABORTED — H1 #13)"
fi
}
