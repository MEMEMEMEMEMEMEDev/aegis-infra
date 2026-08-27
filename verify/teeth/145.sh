# teeth for check 145 (every secret a generator lists is written by a phase)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
P40="init/phases/40-registry-pki.sh"

# the garage line goes back out of phase 40: the state the VPS found
red_1() {
    python3 - "$AEGIS_ROOT/$P40" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = ' \\\n    "regcred-internal:garage-system:$B/garage-system/secret-regcred-internal.enc.yaml"'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "", 1))
PY
}
# a new generator entry nobody writes
red_2() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/garage-system/secret-generator.yaml" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert "secret-regcred-internal.enc.yaml" in t
open(p, "w").write(t.replace("secret-regcred-internal.enc.yaml", "secret-regcred-internal.enc.yaml\n  - secret-garage-admin.enc.yaml", 1))
PY
}
# control: prose is not the contract
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/$P40"; }
