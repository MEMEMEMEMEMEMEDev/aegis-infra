# titulo: todo git push de las fases va verificado
# origen: verify-static.sh (v2) ══ 30, parte a — partida en v3
check() {
# Un push fallido que sigue de largo = commit local sin pushear →
# kustomize roto UNA fase después (corrida #9). Los probe-push
# (bash -c) van con retry_net y su exit propaga por la cadena &&.
BAD_PUSH="$(grep -rn 'git -C .* push' "$FASES/" | nc_hits | grep -v 'git_push_verified' | grep -v 'retry_net' || true)"
if [[ -n "$BAD_PUSH" ]]; then fail "git push SIN verificación:"$'\n'"$BAD_PUSH"
else pass "todo git push verificado (git_push_verified / retry_net)"; fi
}
