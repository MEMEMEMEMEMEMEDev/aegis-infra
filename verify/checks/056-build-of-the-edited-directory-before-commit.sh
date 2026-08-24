# title: build of the edited directory BEFORE the commit (Pattern A-2c in-VM)
# origin: verify-static.sh (v2) ══ 56
check() {
# the error of a bad injection/entry showed up 3 links later:
L_KB="$(grep -n 'kustomize-build-policies' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_PK="$(grep -n 'gate "policy-en-kustomization"' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
# session 21 (class F): phase 80's commit now goes through
# git_commit_if_changes — the anchor is that helper, not the raw git:
L_CM="$(grep -n 'git_commit_if_changes "\$PLATFORM_DIR"' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
if [[ -n "$L_KB" && -n "$L_PK" && -n "$L_CM" ]] && (( L_PK < L_KB && L_KB < L_CM )) \
   && nc "$PHASES/80-supply-chain.sh" \
      | grep -q 'kubectl kustomize.*kyverno-policies'; then
    pass "phase 80 builds kyverno-policies after the entry and before the commit (it fails HERE, not at the sync)"
else
    fail "no local build of the edited dir before the commit (entry=$L_PK build=$L_KB commit=$L_CM)"
fi
}
