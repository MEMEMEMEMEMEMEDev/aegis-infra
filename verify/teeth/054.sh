# teeth for check 054 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'gates.jsonl' "$AEGIS_ROOT/lib/common.sh" > "$AEGIS_ROOT/lib/common.sh.tooth" \
        && mv "$AEGIS_ROOT/lib/common.sh.tooth" "$AEGIS_ROOT/lib/common.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/lib/common.sh"; }

# The third outcome recorded as a PASS: the gate leaves a line, so
# nothing looks missing, and the line says the opposite of the truth.
# It is the most comfortable way to lie in the whole record.
red_2() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    _gate_record "$name" not-evaluated 0\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, '    _gate_record "$name" pass 0\n', 1))
PY
}

# The helper disappears altogether: every phase that declares a gate
# without a subject would go back to saying it only to the human.
red_3() {
    python3 - "$AEGIS_ROOT/lib/common.sh" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"gate_no_subject\(\) \{.*?\n\}\n", "", t, count=1, flags=re.S)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
