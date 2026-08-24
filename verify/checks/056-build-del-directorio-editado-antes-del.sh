# title: build del directorio editado ANTES del commit (Patrón A-2c in-VM)
# origen: verify-static.sh (v2) ══ 56
check() {
# el error de una inyección/entry mala se veía 3 eslabones después:
L_KB="$(grep -n 'kustomize-build-policies' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_PK="$(grep -n 'gate "policy-en-kustomization"' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
# sesión 21 (clase F): el commit de la 80 ahora va por
# git_commit_if_changes — el ancla es ese helper, no el git crudo:
L_CM="$(grep -n 'git_commit_if_changes "\$PLATFORM_DIR"' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
if [[ -n "$L_KB" && -n "$L_PK" && -n "$L_CM" ]] && (( L_PK < L_KB && L_KB < L_CM )) \
   && nc "$PHASES/80-supply-chain.sh" \
      | grep -q 'kubectl kustomize.*kyverno-policies'; then
    pass "la 80 buildea kyverno-policies tras la entry y antes del commit (falla ACÁ, no en el sync)"
else
    fail "sin build local del dir editado antes del commit (entry=$L_PK build=$L_KB commit=$L_CM)"
fi
}
