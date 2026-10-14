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

# ── and ONE of them is run, today ────────────────────────────────────
# A tooth file that exists is not a tooth that bites: six were found
# broken on 2026-09-14 by running them all by hand, after weeks of this
# check saying «every check has a tooth». Running all of them costs
# minutes and belongs to --teeth; running ONE costs 20-60 s and belongs
# here, so that no run of the suite goes by without a tooth being
# exercised (review of 2026-10-13, 4B-4). The pick is DERIVED from the
# commit (or from the list, with no git), never random: the same tree
# samples the same check, and the confirmation pass can reproduce a
# red. This check never samples itself, and never samples inside the
# tooth runner (AEGIS_VERIFY_IN_TOOTH, set by the runner for every
# mutation it runs and for its subject probe): a tooth that runs a
# tooth that runs a tooth is the recursion the guard exists for. The
# sample branch is proven by harness test 15, for the same reason.
SAMPLE199=""
if [[ -n "${AEGIS_VERIFY_IN_TOOTH:-}" ]]; then
    printf '    sample tooth not run: inside the tooth runner (it would be a tooth inside a tooth)\n'
else
    candidates=()
    for c in "$AEGIS_ROOT"/verify/checks/[0-9][0-9][0-9]*.sh; do
        b="$(basename "$c")"; n="${b%%-*}"
        [[ "$n" == 199 ]] && continue
        [[ -f "$AEGIS_ROOT/verify/teeth/$n.sh" ]] && candidates+=("$n")
    done
    seed199="$(git -C "$AEGIS_ROOT" rev-parse HEAD 2>/dev/null)"
    if [[ "$seed199" =~ ^[0-9a-f]{40}$ ]]; then from199="commit ${seed199:0:7}"
    else seed199="$(printf '%s\n' "${candidates[@]}" | sha256sum | cut -c1-40)"; from199="the teeth list (no git here)"; fi
    if [[ ${#candidates[@]} -eq 0 ]]; then
        D199="$D199 no check has a tooth to sample;"
    else
        idx199=$(( 16#${seed199:0:8} % ${#candidates[@]} ))
        # a sampled check that has no subject here (288 without
        # --with-charts) measured nothing: the next one is taken, up to 3
        for _try in 1 2 3; do
            SAMPLE199="${candidates[$idx199]}"
            t0=$SECONDS
            OUT199="$("$AEGIS_ROOT/libexec/aegis-verify" --teeth "$SAMPLE199" --profile "$(profile)" 2>&1)"; RC199=$?
            if grep -q 'no subject under profile' <<<"$OUT199"; then
                printf '    sample %s has no subject here, the next one is taken\n' "$SAMPLE199"
                idx199=$(( (idx199 + 1) % ${#candidates[@]} )); SAMPLE199=""
                continue
            fi
            break
        done
        if [[ -z "$SAMPLE199" ]]; then
            printf '    no sampled check had a subject here (3 tried from %s)\n' "$from199"
        elif (( RC199 == 0 )) && grep -q 'TEETH: they all bite' <<<"$OUT199"; then
            printf '    sampled check %s (picked from %s): %s in %ss\n' "$SAMPLE199" "$from199" \
                "$(sed 's/\x1b\[[0-9;]*m//g' <<<"$OUT199" | grep -oE "$SAMPLE199: [0-9]+/[0-9]+ bite.*" | head -1)" "$(( SECONDS - t0 ))"
        else
            D199="$D199 the sampled check $SAMPLE199 (picked from $from199) does not protect what it claims (rc $RC199): $(sed 's/\x1b\[[0-9;]*m//g' <<<"$OUT199" | grep -E 'DOES NOT BITE|turned RED|could not be applied|UNCHANGED|broke check|selected no mutation' | head -3 | tr '\n' ' ');"
        fi
    fi
fi

if [[ -n "$D199" ]]; then fail "teeth:$D199"
elif [[ -n "$SAMPLE199" ]]; then pass "every check has an executable tooth or is on the debt list, the list does not lie, and the sampled tooth ($SAMPLE199) bites"
else pass "every check has an executable tooth or is on the debt list, and the list does not lie (no tooth sampled here)"; fi
}
