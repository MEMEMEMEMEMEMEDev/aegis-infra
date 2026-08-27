# teeth for check 141 (the instance is seeded before any phase reads it)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# The shape of the bug the VPS found: the copy of the seed happening
# AFTER a phase that reads the instance.
P00="init/phases/00-preflight.sh"

# the call slides below the host-key gate: phase 00 reads before it seeds
red_1() {
    python3 - "$AEGIS_ROOT/$P00" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert t.count("\nseed_platform_dir\n") == 1
t = t.replace("\nseed_platform_dir\n", "\n", 1)
anchor = 'gate "github-hostkeys-vigentes" check_github_hostkeys_pin\n'
assert t.count(anchor) == 1
open(p, "w").write(t.replace(anchor, anchor + "seed_platform_dir\n", 1))
PY
}
# the .git guard disappears: a re-run would copy the seed over a living instance
red_2() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    if [[ -d "$PLATFORM_DIR/.git" ]]; then\n        log_info "platform/ is already an instance (it has .git): NOT seeding from the seed"\n        return 0\n    fi\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "", 1))
PY
}
# phase 10 grows its own copy again: two places to drift
red_3() {
    python3 - "$AEGIS_ROOT/init/phases/10-age-ceremony.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert t.count("\nseed_platform_dir\n") == 1
open(p, "w").write(t.replace("\nseed_platform_dir\n", '\nrun_cmd cp -a "$AEGIS_ROOT/seed/platform/." "$PLATFORM_DIR/"\n', 1))
PY
}
# control: prose around the call is not the contract
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/$P00"; }
