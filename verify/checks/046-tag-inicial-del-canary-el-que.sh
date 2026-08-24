# title: tag inicial del canary = el que EXISTE en el registry (H1 #13)
# origen: verify-static.sh (v2) ══ 46
check() {
F70_NC="$(nc "$PHASES/70-deploy-auto.sh")"
if echo "$F70_NC" | grep -q 'tags/list' \
   && echo "$F70_NC" | grep -q 'tag-real-en-registry' \
   && echo "$F70_NC" | grep -q 'newTag: main-'; then
    pass "fase 70 deriva el tag del registry (gate) y alinea el newTag antes del deploy"
else
    fail "el tag inicial sigue asumiendo el número del build #1 (cosmético ABORTED — H1 #13)"
fi
}
