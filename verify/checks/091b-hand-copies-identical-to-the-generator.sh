# title: the hand-written copies of the middlewares are byte for byte what the generator emits
# origin: verify-static.sh (v2) ══ 91, part (b) — split off in v3
check() {
# The canary has no contract (it is what proves the tenant's path
# works, so it cannot depend on that path), but it needs the three
# middlewares all the same. They are written BY HAND in its
# routes.yaml, and they have to be byte for byte the ones `aegis org`
# generates for any organization with a contract: if somebody touches
# the generator and forgets the copy, the canary is left with the old
# protection and nobody finds out.
#
# In v2 the reference was `org-blog`: a REAL organization of the
# instance, committed in platform/k8s/organizations/. Two problems that
# are only visible from v3: the artifact has no org-blog (nor should it
# — the seed carries no instance inside it, check 86), and a reference
# tied to a concrete name lies the day that organization is deleted.
# The correct reference is not another copy: it is THE GENERATOR.
#
# TO VERIFY (2026-08-23, T-02): wire it up with `from aegis import
# derivar` and compare against the real render_routes(). Until the
# package exists, this is NOT EVALUABLE — and it says so, which is
# different from passing green without having measured anything.
if python3 -c 'import sys; sys.path.insert(0, "'"$AEGIS_ROOT"'/lib"); import aegis.derivar' 2>/dev/null; then
    fail "lib/aegis/derivar.py exists but this check still does not use it — it was promised for T-02 and the promise has come due"
else
    skip "without lib/aegis/derivar.py there is no generator to compare against (T-02); the reference by organization name was deliberately withdrawn"
fi
}
