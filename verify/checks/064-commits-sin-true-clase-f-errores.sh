# titulo: commits SIN || true — clase F (errores tragados)
# origen: verify-static.sh (v2) ══ 64
check() {
# `git commit || true` en 6 fases tragaba fallos REALES: el push
# "exitoso" no llevaba nada y ArgoCD nunca veía el cambio (síntoma 2
# fases después). La distinción es estructural (diff --cached):
D64=""
BAD64="$(for f in "$AEGIS_ROOT"/init/phases/*.sh; do
    sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$f" | nc \
      | grep -E 'git .*commit .*\|\|' | sed "s|^|$(basename "$f"): |"
done)"
[[ -z "$BAD64" ]] || D64="$D64 commits con || vivo: $BAD64;"
GCI64="$(body_of git_commit_if_changes "$LIBS/common.sh")"
echo "$GCI64" | grep -q 'diff --cached --quiet' \
    || D64="$D64 git_commit_if_changes sin la distinción estructural staged-vacío;"
# CINCO fases y no seis desde #59: la 70 commiteaba el CR del Image
# Updater al kustomization, y ese commit se fue con el componente.
N64="$(grep -l 'git_commit_if_changes' "$AEGIS_ROOT"/init/phases/*.sh | wc -l)"
(( N64 >= 5 )) || D64="$D64 solo $N64/5 fases usan git_commit_if_changes;"
if [[ -n "$D64" ]]; then fail "commits:$D64"
else pass "5 fases con commit condicionado a staged real — un commit fallido mata la fase DONDE falla"; fi
}
