# title: every secret an organization's generator declares has somebody in the artifact that makes it
# origin: new in v3 — 2026-09-02, three hand copies of the same regcred on one real install
check() {
# An organization's ksops generator is a CONTRACT WITH ITSELF: it names
# the .enc.yaml files it will decrypt, and kustomize refuses to render
# the organization if one of them is missing. Not the Secret — the whole
# Application. The error is «error reading
# secret-regcred-internal.enc.yaml: no such file or directory», ArgoCD
# reports ComparisonError, and the App still shows Healthy because
# nothing was ever created to be unhealthy.
#
# On a real install `aegis secret create <contract>` made the deploy keys
# and the AI gateway key and answered «no recipe» for the regcred, exit
# 0, three organizations in a row. Each one had to be finished by hand
# with `aegis secret move`, and a step done by hand three times is a
# step that will be forgotten the fourth.
#
# The class is not «the regcred»: it is A GENERATOR THAT DECLARES A FILE
# NOBODY MAKES. Check 145 asks that of the platform's namespaces, where
# the maker is an init phase; this one asks it of the ORGANIZATIONS,
# where the maker has to be the command that turns a contract into an
# instance — an organization is signed up after the init, with no phase
# left to run.
#
# The set is DERIVED, twice and from the same truth: the generators the
# seed ships, and `org.secrets_of` — the function that renders every one
# of them — asked for the maximal contract it can be given. A list
# written here would be a list that goes stale the day a contract learns
# a new word, which is exactly how three consumer lists in this repo
# went stale in a single day.
#
# And the question is put to the COMMAND, by running it, not by reading
# it: see verify/checks/172.py for why.
[[ -d "$SEED/platform/k8s/organizations" ]] \
    || { skip "the seed carries no k8s/organizations/: no organization declares anything here"; return; }

D172=""
# A scan that dies has to take the check with it. Check 166 was green
# over a broken file because a sed printed nothing, and green-on-silence
# is the one failure this verifier exists to make impossible.
if ! OUT="$(python3 "$AEGIS_ROOT/verify/checks/172.py" "$AEGIS_ROOT" 2>/dev/null)"; then
    D172="$D172 the scan itself failed and this check measured nothing;"
elif [[ "$OUT" == __NOSUBJECT__* ]]; then
    skip "${OUT#__NOSUBJECT__ }"; return
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D172="$D172 $hit;"
    done <<< "$OUT"
fi
TALLY="$(python3 "$AEGIS_ROOT/verify/checks/172.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2" declared · "$3" invented · "$4" copied from the namespace that already holds them"}')"

printf '    %s\n' "${TALLY:-nothing measured}"
if [[ -n "$D172" ]]; then fail "an organization declares a secret nobody makes:$D172"
else pass "every .enc.yaml an organization's generator declares is one \`aegis secret create\` either invents or derives from the namespace that already holds it, so signing an organization up needs no hand copy"; fi
}
