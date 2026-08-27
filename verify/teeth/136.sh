# teeth for check 136 (every scan exception is dated, bounded and justified)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# The file's first entries: 15 gosu CVEs measured 2026-07-26, expiring
# 2027-01-31. Each red takes one of the three bounds off ONE entry.
TI="seed/platform/mirror-images/trivyignore.yaml"

# an exception with no end
red_1() {
    python3 - "$AEGIS_ROOT/$TI" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"(- id: CVE-2025-68121.*?\n(?:    .*\n)*?)    expired_at: \S+\n", r"\1", t, count=1, flags=re.S)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# an end three years after the measurement: a permanent hole with a
# date on it
red_2() {
    python3 - "$AEGIS_ROOT/$TI" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "    expired_at: 2027-01-31\n"
assert old in t
open(p, "w").write(t.replace(old, "    expired_at: 2029-07-26\n", 1))
PY
}
# no paths: the CVE is silenced wherever it shows up
red_3() {
    python3 - "$AEGIS_ROOT/$TI" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    paths: ["usr/local/bin/gosu"]\n'
assert old in t
open(p, "w").write(t.replace(old, "    paths: []\n", 1))
PY
}
# control: rewording the justification (keeping its date) is exactly
# what a re-measurement does
control_1() {
    python3 - "$AEGIS_ROOT/$TI" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'statement: "crypto/tls is not linked into the binary (0 symbols). Measured 2026-07-26."'
assert old in t
open(p, "w").write(t.replace(old, 'statement: "The TLS package is absent from the binary: zero crypto/tls symbols. Measured 2026-07-26."', 1))
PY
}
