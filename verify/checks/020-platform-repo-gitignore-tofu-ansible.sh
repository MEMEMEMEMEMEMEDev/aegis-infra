# title: the platform repo's .gitignore (tofu/ansible)
# origin: verify-static.sh (v2) ══ 20
check() {
# Run #4: git add -A pushed .terraform/ (233MB, GitHub rejects it) and
# the tfstate. ansible's venv is the same class:
GI="$P/.gitignore"
GI_MISS=""
for pat in '.terraform/' '*.tfstate' 'ansible/.venv'; do
    grep -qF "$pat" "$GI" 2>/dev/null || GI_MISS="$GI_MISS $pat"
done
if [[ -n "$GI_MISS" ]]; then fail "platform/.gitignore does not cover:$GI_MISS"
else pass ".gitignore covers .terraform/, tfstate and ansible's venv"; fi
}
