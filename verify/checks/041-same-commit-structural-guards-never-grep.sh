# title: same-commit: STRUCTURAL guards, never a textual grep (H4 #13, SYSTEMIC)
# origin: verify-static.sh (v2) ══ 41
check() {
# the grep -q by NAME matched the COMMENT that documents the pattern →
# the entry was never added → orphaned resource (2 live: the IU's CR +
# the IU's regcred; 2 latent: cosign + policy). Rule: every guard over
# YAML lists uses yaml_lists_file (the real entry) and VERIFIES the
# result with a gate — || true does not swallow steps:
D41=""
grep -q '^yaml_lists_file()' "$LIBS/common.sh" \
    || D41="$D41 yaml_lists_file missing from common.sh;"
BAD41="$(grep -rn 'grep -q' "$PHASES/" \
    | nc_hits \
    | grep -E "grep -q ['\"][^'\"]*\.yaml['\"]" || true)"
[[ -n "$BAD41" ]] && D41="$D41 textual grep over a .yaml name (it matches comments):"$'\n'"$BAD41"
N_USES="$(grep -rh 'yaml_lists_file' "$PHASES/" | grep -vcE '^\s*#')"
# TWO same-commit and not four since #59, with two uses each (guard +
# gate). The two of the Image Updater are gone: the one in phase 40,
# which added its regcred to the generator's list, and the one in phase
# 70, which added its CR to the kustomization. The ones in phase 80
# remain: the cosign key and the signature ClusterPolicy.
(( N_USES >= 4 )) || D41="$D41 yaml_lists_file used $N_USES times (expected >=4: guard+gate in the 2 same-commit);"
if [[ -n "$D41" ]]; then fail "fragile same-commit:$D41"
else pass "structural same-commit guards (yaml_lists_file x$N_USES) and with a result gate"; fi
}
