# title: .gitignore del repo de plataforma (tofu/ansible)
# origen: verify-static.sh (v2) ══ 20
check() {
# Corrida #4: git add -A pusheó .terraform/ (233MB, GitHub rechaza)
# y el tfstate. El venv de ansible es la misma clase:
GI="$P/.gitignore"
GI_MISS=""
for pat in '.terraform/' '*.tfstate' 'ansible/.venv'; do
    grep -qF "$pat" "$GI" 2>/dev/null || GI_MISS="$GI_MISS $pat"
done
if [[ -n "$GI_MISS" ]]; then fail "platform/.gitignore no cubre:$GI_MISS"
else pass ".gitignore cubre .terraform/, tfstate y el venv de ansible"; fi
}
