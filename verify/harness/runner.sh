#!/usr/bin/env bash
# harness/runner.sh — the verifier verifying itself.
#
# The runner promises three things no check can guarantee on its own:
# that a mute check is red, that a self-contradicting check is a bug (and
# not a verdict), and that --only does not invent selections. If any of
# them breaks, ALL the checks are worth less — which is why this runs
# before them.
set -u
: "${AEGIS_ROOT:?}"
FAILURES=0
ok()  { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAILURES=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/libexec" "$TMP/verify/checks" "$TMP/verify/teeth"
cp "$AEGIS_ROOT/libexec/aegis-verify" "$TMP/libexec/"
cp "$AEGIS_ROOT/verify/lib.sh" "$TMP/verify/"
V() { AEGIS_ROOT="$TMP" "$TMP/libexec/aegis-verify" "$@"; }

# 1. a normal check: PASS → rc 0
cat > "$TMP/verify/checks/001-fake.sh" <<'C'
# title: fake check that passes
check() { pass "all good"; }
C
V --only 001 --profile cloudflare >/dev/null 2>&1
[[ $? == 0 ]] && ok "a passing check gives rc 0" || bad "a passing check did NOT give rc 0"

# 2. a failing check → rc 1
cat > "$TMP/verify/checks/002-red.sh" <<'C'
# title: check that fails
check() { fail "something is missing"; }
C
V --only 002 --profile cloudflare >/dev/null 2>&1
[[ $? == 1 ]] && ok "a failing check gives rc 1" || bad "a failing check did NOT give rc 1"

# 3. THE MISSING LINE: a check that says nothing is NOT green
cat > "$TMP/verify/checks/003-mute.sh" <<'C'
# title: mute check (emits no verdict)
check() { local x=1; : "$x"; }
C
OUT="$(V --only 003 --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 1 ]] && grep -q 'emitted no verdict' <<<"$OUT" \
    && ok "a mute check is FAIL, not silence" \
    || bad "a mute check was NOT red (rc=$RC)"

# 4. two verdicts = verifier bug (exit 3), not a result
cat > "$TMP/verify/checks/004-double.sh" <<'C'
# title: check that emits two verdicts
check() { pass "one"; fail "and another"; }
C
OUT="$(V --only 004 --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 3 ]] && grep -q 'emitted 2 verdicts' <<<"$OUT" \
    && ok "two verdicts = exit 3 (verifier bug)" \
    || bad "two verdicts did NOT give exit 3 (rc=$RC)"

# 5. a file with no check() is not a check
cat > "$TMP/verify/checks/005-no-function.sh" <<'C'
# title: file that does not define check()
echo "hello"
C
V --only 005 --profile cloudflare >/dev/null 2>&1
[[ $? == 3 ]] && ok "a file with no check() = exit 3" || bad "a file with no check() did NOT give exit 3"

# 6. a check that blows up halfway does not pass as green
cat > "$TMP/verify/checks/006-explodes.sh" <<'C'
# title: check that blows up before emitting
check() { echo "$THIS_VARIABLE_DOES_NOT_EXIST"; pass "I never get here"; }
C
V --only 006 --profile cloudflare >/dev/null 2>&1
[[ $? == 1 ]] && ok "a check that blows up before its verdict is red" || bad "a check that blows up was NOT red"

# 7. --only with a nonexistent number does not run nothing IN SILENCE
V --only 999 --profile cloudflare >/dev/null 2>&1
[[ $? == 3 ]] && ok "--only nonexistent = error, not an empty run" || bad "--only nonexistent did NOT error"

# 8. with no checks, the verifier cannot be green
mkdir -p "$TMP/empty/verify/checks" "$TMP/empty/libexec"
cp "$TMP/libexec/aegis-verify" "$TMP/empty/libexec/"; cp "$TMP/verify/lib.sh" "$TMP/empty/verify/"
AEGIS_ROOT="$TMP/empty" "$TMP/empty/libexec/aegis-verify" >/dev/null 2>&1
[[ $? == 3 ]] && ok "zero checks is NOT green" || bad "zero checks came out green"

# 9. the teeth: a red that does not bite gets reported
cat > "$TMP/verify/checks/007-with-tooth.sh" <<'C'
# title: check with a tooth
check() { grep -q 'sentinel' "$AEGIS_ROOT/verify/mark.txt" && pass "the mark is there" || fail "the mark is missing"; }
C
echo "sentinel" > "$TMP/verify/mark.txt"
cat > "$TMP/verify/teeth/007.sh" <<'C'
red_1()     { sed -i 's/sentinel/something-else/' "$AEGIS_ROOT/verify/mark.txt"; }
control_1() { printf 'a new comment\n' >> "$AEGIS_ROOT/verify/mark.txt"; }
C
V --only 007 --teeth --profile cloudflare >/dev/null 2>&1
[[ $? == 0 ]] && ok "a biting tooth passes --teeth" || bad "a legitimate tooth did NOT pass --teeth"

cat > "$TMP/verify/teeth/007.sh" <<'C'
red_1() { printf 'this breaks nothing\n' >> "$AEGIS_ROOT/verify/mark.txt"; }
C
OUT="$(V --only 007 --teeth --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 1 ]] && grep -q 'DOES NOT BITE' <<<"$OUT" \
    && ok "a tooth that does NOT bite gets reported" \
    || bad "a useless tooth passed as good (rc=$RC)"

# 10. a control that turns red is also reported
cat > "$TMP/verify/teeth/007.sh" <<'C'
red_1()     { sed -i 's/sentinel/something-else/' "$AEGIS_ROOT/verify/mark.txt"; }
control_1() { : > "$AEGIS_ROOT/verify/mark.txt"; }
C
OUT="$(V --only 007 --teeth --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 1 ]] && grep -q 'turned RED' <<<"$OUT" \
    && ok "a control that turns red gets reported" \
    || bad "a check that bites too much passed (rc=$RC)"

# 10b. --teeth with a number that selects nothing is NOT success.
# Found on 2026-08-24: the filter compared the number as a STRING, so
# `--teeth 39` never matched check 039 (only a leading "00" was
# stripped, so 039 stayed 039). Nothing ran, and the caller announced
# "TEETH: they all bite". A selection that matches nothing reported as
# green is the disease the verifier exists to kill, living inside the
# verifier.
OUT="$(V --only 007 --teeth 999 --profile cloudflare 2>&1)"; RC=$?
[[ $RC != 0 ]] && grep -q 'selected no mutation' <<<"$OUT" \
    && ok "--teeth with a number that selects nothing is an error, not a green" \
    || bad "--teeth 999 came out green (rc=$RC)"

# and the number is matched NUMERICALLY: a two-digit query has to find
# the three-digit filename.
mv "$TMP/verify/checks/007-with-tooth.sh" "$TMP/verify/checks/039-with-tooth.sh"
mv "$TMP/verify/teeth/007.sh" "$TMP/verify/teeth/039.sh"
cat > "$TMP/verify/teeth/039.sh" <<'C'
red_1()     { sed -i 's/sentinel/something-else/' "$AEGIS_ROOT/verify/mark.txt"; }
control_1() { printf 'a new comment\n' >> "$AEGIS_ROOT/verify/mark.txt"; }
C
echo "sentinel" > "$TMP/verify/mark.txt"
OUT="$(V --only 039 --teeth 39 --profile cloudflare 2>&1)"; RC=$?
[[ $RC == 0 ]] && grep -q '1/1 bite' <<<"$OUT" \
    && ok "--teeth 39 finds check 039 (numeric match, not string)" \
    || bad "--teeth 39 did NOT select check 039 (rc=$RC)"

# 11. the profile that does NOT exist yet: rc 2, not a red and not a green
cat > "$TMP/verify/checks/008-profile.sh" <<'C'
# title: any old check
check() { pass "nothing"; }
C
# What makes the local edge EXIST is derived from two owners: the config
# validator accepting it, and the bridge that serves it shipping. The
# harness has to simulate the SAME two facts — until 2026-08-26 it planted
# an `__EDGE_MODE__` marker in a fake seed, which was the old signal, and
# it went red the day the signal started asking the right question. A
# harness that simulates a mechanism has to move with it, or it measures
# a world that no longer exists.
mkdir -p "$TMP/seed" "$TMP/lib" "$TMP/share/systemd"
V --only 008 --profile local >/dev/null 2>&1
[[ $? == 2 ]] && ok "an edge the artifact does not implement = rc 2" \
    || bad "--profile local with no local edge in the tree did NOT give rc 2"

# half the evidence is not evidence: the validator accepts the edge, but
# nothing serves it
printf '_v_edge()    { [[ "$1" == cloudflare || "$1" == local ]]; }\n' > "$TMP/lib/config.sh"
V --only 008 --profile local >/dev/null 2>&1
[[ $? == 2 ]] && ok "the conf accepts the edge but no bridge serves it = still rc 2" \
    || bad "--profile local ran with a validator that accepts local and NO bridge"

# and with both halves it runs
touch "$TMP/share/systemd/aegis-edge-http.socket"
V --only 008 --profile local >/dev/null 2>&1
[[ $? == 0 ]] && ok "with the edge implemented (validator + bridge), it runs" \
    || bad "--profile local did NOT run with the local edge implemented"

# 12. the confirmation pass (H2) re-runs THE SAME selection. Until
# 2026-10-14 the argument loop had consumed "$@" before the pass re-ran
# `"$0" "$@"`, so a `--only` of one failing check re-ran the whole suite
# in both profiles, and the teeth — one run per mutation — took hours
# (review of 2026-10-13, F3). A check that records every run and is NOT
# selected must never run.
cat > "$TMP/verify/checks/012-fails.sh" <<'C'
# title: a check that fails, selected alone
check() { fail "still red"; }
C
cat > "$TMP/verify/checks/013-counts.sh" <<'C'
# title: a check that records every run
check() { printf 'ran\n' >> "$AEGIS_ROOT/verify/ran-013"; pass "counted"; }
C
rm -f "$TMP/verify/ran-013"
OUT="$(AEGIS_VERIFY_RETRY='' V --only 012 --profile cloudflare 2>&1)"; RC=$?
n=0; [[ -f "$TMP/verify/ran-013" ]] && n="$(wc -l < "$TMP/verify/ran-013")"
[[ $RC == 1 && "${n:-0}" == 0 ]] && grep -q 'REPRODUCED' <<<"$OUT" \
    && ok "the confirmation pass keeps the selection: an unselected check never ran" \
    || bad "the confirmation pass dropped the arguments: the unselected check ran ${n:-0} time(s) (rc=$RC)"
rm -f "$TMP/verify/checks/012-fails.sh" "$TMP/verify/checks/013-counts.sh" "$TMP/verify/ran-013"

# 13. two profiles are two passes only when a check reads the profile.
# The sandbox implements the local edge since test 11, so `both` used to
# run every check twice over the same tree (review of 2026-10-13, F1).
cat > "$TMP/verify/checks/014-counts.sh" <<'C'
# title: a check that records every run
check() { printf 'ran\n' >> "$AEGIS_ROOT/verify/ran-014"; pass "counted"; }
C
rm -f "$TMP/verify/ran-014"
OUT="$(V --only 014 --profile both 2>&1)"; RC=$?
n=0; [[ -f "$TMP/verify/ran-014" ]] && n="$(wc -l < "$TMP/verify/ran-014")"
[[ $RC == 0 && "${n:-0}" == 1 ]] && grep -q 'no check reads the profile' <<<"$OUT" \
    && ok "with no check reading the profile, --profile both is one pass, and it is said" \
    || bad "--profile both ran the check ${n:-0} time(s) with no check reading the profile (rc=$RC)"
cat > "$TMP/verify/checks/015-reads-profile.sh" <<'C'
# title: a check that reads the profile
check() { printf 'ran\n' >> "$AEGIS_ROOT/verify/ran-015"; pass "under ${AEGIS_VERIFY_PROFILE:-?}"; }
C
rm -f "$TMP/verify/ran-014" "$TMP/verify/ran-015"
V --only 014 --only 015 --profile both >/dev/null 2>&1; RC=$?
n=0; [[ -f "$TMP/verify/ran-014" ]] && n="$(wc -l < "$TMP/verify/ran-014")"
m=0; [[ -f "$TMP/verify/ran-015" ]] && m="$(wc -l < "$TMP/verify/ran-015")"
[[ $RC == 0 && "${n:-0}" == 2 && "${m:-0}" == 2 ]] \
    && ok "the day a check reads the profile, both passes run again" \
    || bad "with a check that reads the profile, the passes were $n and $m, not 2 and 2 (rc=$RC)"
rm -f "$TMP/verify/checks/014-counts.sh" "$TMP/verify/checks/015-reads-profile.sh" "$TMP/verify/ran-014" "$TMP/verify/ran-015"

exit $FAILURES
