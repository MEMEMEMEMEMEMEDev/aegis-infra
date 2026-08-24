# title: '|| true' only where it is legitimate
# origin: verify-static.sh (v2) ══ 9
check() {
# legitimate: git commit (nothing to commit), best-effort cleanup,
# inventory greps. Illegitimate: over secrets/gates/apply.
BAD="$(grep -rn '|| true' "$PHASES" \
    | nc_hits \
    | grep -vE 'git .*commit|--no-verify|log_info|kustomization.yaml 2>/dev/null' \
    | grep -vE '>&2 \|\| true' \
    | grep -vE '\|\| true\)"$' \
    || true)"
# ('>&2 || true' = best-effort evidence dump to stderr on a diagnostic
#  path; '|| true)"' = a $(...) capture with an empty fallback that a
#  later [[ ]] evaluates explicitly — neither one swallows the result
#  of a gate)
if [[ -n "$BAD" ]]; then fail "suspicious '|| true':"$'\n'"$BAD"
else pass "'|| true' audited (only idempotent commits)"; fi
}
