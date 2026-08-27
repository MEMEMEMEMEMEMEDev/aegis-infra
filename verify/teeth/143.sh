# teeth for check 143 (phase 05 puts aegis on the PATH it promises)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
P05="init/phases/05-host.sh"

# the install disappears: back to the state the VPS found
red_1() {
    python3 - "$AEGIS_ROOT/$P05" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'run_cmd sudo ln -sfn "$AEGIS_ROOT/bin/aegis" /usr/local/bin/aegis\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "", 1))
PY
}
# the install stays, the gate goes: written and never measured
red_2() {
    python3 - "$AEGIS_ROOT/$P05" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r'gate "aegis-en-path" bash -c \\\n[^\n]*\n', "", t, count=1)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# control: prose is not the contract
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/$P05"; }
