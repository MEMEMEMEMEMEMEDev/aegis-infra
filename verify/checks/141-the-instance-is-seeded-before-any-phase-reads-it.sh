# title: the instance's platform/ is seeded before any phase reads it
# origin: new in v3 — 2026-08-27, the first init on a machine where product and instance are not the same folder
check() {
# Product != instance. seed/platform/ ships with the artifact; the
# instance's $PLATFORM_DIR is born by copying it. The copy used to live
# in phase 10, and phases 00 (GitHub host-key pins) and 05 (userland
# pins) read $PLATFORM_DIR before that — invisible on the house
# machine, where both are one folder, fatal on the VPS: phase 00 died
# with a python traceback on a path nobody had created. This check
# nails the order down: the seeding is one function with the .git
# guard, phase 00 calls it before anything in the run reads the
# instance, and phase 10 calls the same function instead of carrying a
# copy of its own.
D141=""
CM="$LIBS/common.sh"
FN="$(body_of seed_platform_dir "$CM")"
if [[ -z "$FN" ]]; then
    D141="$D141 lib/common.sh does not define seed_platform_dir (the seeding lives in one place, or it drifts);"
else
    echo "$FN" | grep -q 'PLATFORM_DIR/\.git' \
        || D141="$D141 seed_platform_dir has no .git guard: re-running the init would copy the seed OVER a living instance;"
    echo "$FN" | grep -q 'cp -a' \
        || D141="$D141 seed_platform_dir does not copy with cp -a (modes and dotfiles would be lost);"
fi
P00="$(nc "$PHASES/00-preflight.sh")"
SEED_LINE="$(echo "$P00" | grep -n 'seed_platform_dir' | head -1 | cut -d: -f1)"
if [[ -z "$SEED_LINE" ]]; then
    D141="$D141 phase 00 does not call seed_platform_dir (phase 00 itself and phase 05 read platform/ before phase 10);"
else
    # the first line of phase 00 that reads the instance (directly, or
    # through the host-key gate, whose reader lives in checks.sh)
    FIRST_READ="$(echo "$P00" | grep -n -E 'PLATFORM_DIR|github-hostkeys-vigentes' | head -1 | cut -d: -f1)"
    [[ -n "$FIRST_READ" && "$FIRST_READ" -lt "$SEED_LINE" ]] \
        && D141="$D141 phase 00 reads platform/ at line $FIRST_READ but seeds it at line $SEED_LINE;"
fi
# every phase before 10 that reads platform/ is covered by phase 00's call
for f in "$PHASES"/0[1-9]-*.sh; do
    [[ -f "$f" ]] || continue
    nc "$f" | grep -q 'PLATFORM_DIR' && [[ -z "$SEED_LINE" ]] \
        && D141="$D141 $(basename "$f") reads platform/ and nothing before it seeds it;"
done
P10="$(nc "$PHASES/10-age-ceremony.sh")"
echo "$P10" | grep -q 'seed_platform_dir' \
    || D141="$D141 phase 10 does not call seed_platform_dir (it stops being whole under --only);"
echo "$P10" | grep -q 'cp -a.*seed' \
    && D141="$D141 phase 10 still carries its own copy of the seeding (two places drift);"
printf '    seeding at phase 00 line %s · readers before phase 10: %s\n' "${SEED_LINE:-none}" \
    "$(for f in "$PHASES"/0[0-9]-*.sh; do nc "$f" | grep -q -E 'PLATFORM_DIR|github-hostkeys-vigentes' && basename "$f" .sh; done | tr '\n' ' ')"
if [[ -n "$D141" ]]; then fail "seeding order:$D141"
else pass "platform/ is seeded by one guarded function, in phase 00 before any read, and phase 10 reuses it"; fi
}
