# teeth of check 191 — what aegis leaves the machine is a step in
# plans.yaml, and no reader keeps its own copy of a threshold.

# THE REGRESSION THAT WAS MEASURED, run backwards: the free-disk
# threshold written down again inside the init's gate. That was the
# artifact's real state until 2026-09-09 — 20 here, 25 in
# `aegis preflight`, 25 in both READMEs, and no way to tell which one
# was the requirement.
red_1() {
    python3 - "$AEGIS_ROOT/init/phases/00-preflight.sh" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'gate "disco-suficiente" bash -c \'(?:.|\n)*?\'\n',
           'gate "disco-20G" bash -c \\\n'
           "    '[[ $(df --output=avail -BG / | tail -1 | tr -dc 0-9) -ge 20 ]]'\n",
           s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the other reader keeping its own copy, which is the same defect seen
# from the side that used to disagree.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-preflight" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('elif [ "$H_DISK_G" -ge "$DISK_MIN_G" ]; then',
              'elif [ "$H_DISK_G" -ge 25 ]; then')
open(p, "w", encoding="utf-8").write(s)
PY
}

# a step that covers RAM and forgets VRAM. Half a floor: the missing
# half derives as nothing, and nothing is what `user.slice` had on the
# day the session froze.
red_3() {
    python3 - "$AEGIS_ROOT/seed/platform/plans.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("  exprimido:\n    ram: 4Gi\n    vram: 1Gi\n",
              "  exprimido:\n    ram: 4Gi\n")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the reservations gone. The floor alone under-reserves the node, and
# it does so while looking perfectly derived.
red_4() {
    python3 - "$AEGIS_ROOT/seed/platform/plans.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\n  reservas:\n(?:    [^\n]*\n|    # [^\n]*\n)*', "\n", s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the derivation moved back into python. This is the defect this check
# found in its own first hour: one line mapping "shared" to a step
# name, and the step names living in two files again.
red_5() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('    kind = SHARED_KEY if shared else DEDICATED_KEY\n'
              '    step = anfitrion["por_omision"][kind]\n',
              '    step = "compartido" if shared else "dedicado"\n')
open(p, "w", encoding="utf-8").write(s)
PY
}

# a floor number inlined in the code that derives it.
red_6() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('        "ram_bytes": quantity.mem(s["ram"]),',
              '        "ram_bytes": quantity.mem(s.get("ram") or "6Gi"),')
open(p, "w", encoding="utf-8").write(s)
PY
}

# and the whole section taken away: with no `anfitrion:`, finding no
# bad floor must NOT be reported as everything fine.
red_7() {
    python3 - "$AEGIS_ROOT/seed/platform/plans.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("\nanfitrion:\n", "\nanfitrion_viejo:\n", 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: another non-step setting in the section. The check derives
# what is not a step from the module that owns the shape, so growing
# the section has to stay green.
control_1() {
    python3 - "$AEGIS_ROOT/seed/platform/plans.yaml" "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
plans, lib = sys.argv[1], sys.argv[2]
s = open(plans, encoding="utf-8").read()
s = s.replace("  disco_minimo: 25Gi", "  disco_minimo: 25Gi\n  nucleos_minimos: 4")
open(plans, "w", encoding="utf-8").write(s)
t = open(lib, encoding="utf-8").read()
t = t.replace('NON_STEPS = ("reservas", "disco_minimo", "por_omision")',
              'NON_STEPS = ("reservas", "disco_minimo", "por_omision", "nucleos_minimos")')
open(lib, "w", encoding="utf-8").write(t)
PY
}

# control: changing what a step is WORTH. That is the edit this whole
# section exists to make cheap, and it must never turn the check red.
control_2() {
    sed -i 's|^    ram: 6Gi$|    ram: 5Gi|' "$AEGIS_ROOT/seed/platform/plans.yaml"
}

# control: prose in the derivation naming a step. The check reads code
# with comments and docstrings stripped, so an explanation must not
# count as a hardcoded name.
control_3() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("def floor(anfitrion, facts):",
              "# a legitimate note: on this machine the derived step is compartido,\n"
              "# and the operator may well prefer exprimido or dedicado instead.\n"
              "def floor(anfitrion, facts):")
open(p, "w", encoding="utf-8").write(s)
PY
}
