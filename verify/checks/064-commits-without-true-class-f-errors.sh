# title: commits WITHOUT || true — class F (swallowed errors)
# origin: verify-static.sh (v2) ══ 64
check() {
# `git commit || true` in 6 phases swallowed REAL failures: the
# "successful" push carried nothing and ArgoCD never saw the change
# (symptom 2 phases later). The distinction is structural
# (diff --cached):
D64=""
BAD64="$(for f in "$AEGIS_ROOT"/init/phases/*.sh; do
    sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$f" | nc \
      | grep -E 'git .*commit .*\|\|' | sed "s|^|$(basename "$f"): |"
done)"
[[ -z "$BAD64" ]] || D64="$D64 commits with a live ||: $BAD64;"
GCI64="$(body_of git_commit_if_changes "$LIBS/common.sh")"
echo "$GCI64" | grep -q 'diff --cached --quiet' \
    || D64="$D64 git_commit_if_changes without the structural empty-staged distinction;"
# FIVE phases and not six since #59: phase 70 used to commit the Image
# Updater's CR to the kustomization, and that commit left with the
# component.
N64="$(grep -l 'git_commit_if_changes' "$AEGIS_ROOT"/init/phases/*.sh | wc -l)"
(( N64 >= 5 )) || D64="$D64 only $N64/5 phases use git_commit_if_changes;"
if [[ -n "$D64" ]]; then fail "commits:$D64"
else pass "5 phases with a commit conditioned on real staged content — a failed commit kills the phase WHERE it fails"; fi
}
