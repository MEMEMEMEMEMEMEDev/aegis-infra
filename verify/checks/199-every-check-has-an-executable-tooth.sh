# title: META — every check has an executable tooth
# origin: V-199 (06 §1) — new in v3
check() {
# The verifier's most expensive lesson from v2: «19 mutations, 19
# correctly classified» was true the day it was written and never
# again. The teeth were tested by hand once and then forgotten, and
# three times it turned out the tooth was biting the check itself
# instead of the artifact.
#
# A check without a tooth is a promise without proof: it may be
# measuring thin air (an empty subject, a path that no longer exists, a
# pattern that never appears) and pass green forever. This meta-check
# demands that each one have its teeth file.
#
# The ALLOWLIST (teeth/PENDIENTES) exists because porting 104 teeth is
# not done in one sitting, and a rule that cannot be satisfied today
# switches itself off. But it has two locks: it cannot name checks that
# do not exist, and it cannot name checks that ALREADY have a tooth —
# otherwise, the day somebody adds a check and puts it in there «for
# now», nobody finds out. And the number has to go down: v3.0 does not
# ship with the list populated (09 M-20).
D199=""
PEND="$AEGIS_ROOT/verify/teeth/PENDIENTES"
declare -A pending=()
if [[ -f "$PEND" ]]; then
    while read -r n _; do
        [[ -z "$n" || "$n" == \#* ]] && continue
        pending["$n"]=1
    done < "$PEND"
fi
without_tooth=() ; with_tooth=0
for c in "$AEGIS_ROOT"/verify/checks/[0-9][0-9][0-9]*.sh; do
    b="$(basename "$c")"; n="${b%%-*}"
    if [[ -f "$AEGIS_ROOT/verify/teeth/$n.sh" ]]; then
        with_tooth=$((with_tooth+1))
        [[ -n "${pending[$n]:-}" ]] && D199="$D199 $n is in PENDIENTES but ALREADY has a tooth (the list covers up new holes);"
        unset 'pending[$n]'
    else
        [[ -n "${pending[$n]:-}" ]] && { unset 'pending[$n]'; continue; }
        without_tooth+=("$n")
    fi
done
[[ ${#without_tooth[@]} -eq 0 ]] \
    || D199="$D199 without a tooth and without being declared in PENDIENTES: ${without_tooth[*]};"
[[ ${#pending[@]} -eq 0 ]] \
    || D199="$D199 PENDIENTES names checks that do not exist: ${!pending[*]};"
printf '    %s checks with a tooth · %s on the debt list (it has to reach 0 before v3.0)\n' \
    "$with_tooth" "$(grep -cvE '^\s*(#|$)' "$PEND" 2>/dev/null || echo 0)"
if [[ -n "$D199" ]]; then fail "teeth:$D199"
else pass "every check has an executable tooth or is on the debt list, and the list does not lie"; fi
}
