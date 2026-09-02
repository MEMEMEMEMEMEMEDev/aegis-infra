# title: a tenant AppProject is applied AFTER it is derived, not only at an init that had no tenants
# origin: new in v3 — 2026-09-02, after a real install left every Application at "project not found"
check() {
# MEASURED 2026-09-01 on an install from zero.
#
# `aegis org` DERIVES one AppProject per organization into
# k8s/bootstrap/appprojects-tenants.yaml. Those projects are deliberately
# outside the App-of-Apps path — an App that could edit AppProjects is a
# privilege-escalation vector (W-06 / R1-B) — so NOTHING in GitOps applies
# them. The only automatic applier is the init's phase 35.
#
# And phase 35 runs during the init, when orgs/ is empty. It says so
# itself: «0 contracts in orgs/, nothing to derive». Organizations arrive
# AFTER the init — always, because an init has no tenants — so on the day
# it matters the one automatic path has already run, over an empty file.
#
# What that cost: the new organization's Applications sat at
#
#     Application referencing project aegis-tenant-portafolio
#     which does not exist
#
# nothing deployed, and it took a `kubectl apply -f` typed by hand.
#
# THE CLASS, which is not «the AppProjects»: an artifact whose moment of
# APPLICATION is a fixed instant of the init, while its moment of
# EXISTENCE is whenever a contract arrives. The two are not the same
# clock, and pinning the first to the second is what this check demands.
#
# The generator cannot be the one that applies it, and that is not
# timidity: `aegis org apply` runs from a laptop over a checkout, and this
# very verifier runs it over throwaway copies of the tree. A generator
# that reached for a kubeconfig would reach for the REAL one, from a
# harness, with write verbs. So what is demanded is the honest form: the
# run that DERIVES the projects hands the step over — by name, with the
# exact command, on every run that leaves projects derived (and not only
# on the one that changed the file, which is how it went silent exactly
# when the operator repeated the command), and at the END, where the
# reading finishes.
#
# The scan RUNS the generator over a copy of the seed and reads what it
# printed. It lives in its own python file: a shell scan that dies prints
# nothing and turns the check green (check 166), and a grep over this repo
# reads the paragraph that explains the defect and accuses the file that
# fixes it (checks 161, 163, 165, 166, 167, 168 — six times in one day).
D173=""
if ! OUT="$(python3 "$AEGIS_ROOT/verify/checks/173.py" "$AEGIS_ROOT" 2>/dev/null)"; then
    D173="$D173 the scan itself failed and this check measured nothing;"
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D173="$D173 $hit;"
    done <<< "$OUT"
fi
N173="$(python3 "$AEGIS_ROOT/verify/checks/173.py" "$AEGIS_ROOT" 2>&1 >/dev/null \
        | awk '/__COUNT__/{print $2}')"

printf '    %s tenant AppProject(s) derived from the fixture contract\n' "${N173:-0}"
if [[ -n "$D173" ]]; then fail "a derived tenant AppProject has no path that applies it:$D173"
else pass "every tenant AppProject the generator derives is handed over with the command that applies it — by name, on every run that derives it, at the end of the run — and phase 35 still applies the file, guarded, without calling an empty one a success"; fi
}
