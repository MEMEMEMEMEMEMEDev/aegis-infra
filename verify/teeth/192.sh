# teeth of check 192 — what the cluster reserves is summed against the
# room the host leaves, tmpfs included and the two verdicts apart.

# THE BLIND SPOT THAT WAS MEASURED, put back: the tmpfs term dropped
# from the walk. That was the state of every account in the product on
# 2026-09-09 — 2 GiB of the house machine spoken for by two manifests
# and invisible to the scheduler, to the quota, and to anybody adding
# up what the platform asks for.
red_1() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'    tmpfs = 0\n(?:.*\n)*?            tmpfs \+= quantity\.mem\(ed\["sizeLimit"\]\)\n',
           "    tmpfs = 0\n", s)
open(p, "w", encoding="utf-8").write(s)
PY
}

# the same term dropped one step later: counted in the walk and left
# out of the sum. The number changes and nothing in the shape of the
# code looks wrong.
red_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('    reserves = w["requests"] + w["tmpfs"]\n'
              '    takes = w["limits"] + w["tmpfs"]\n',
              '    reserves = w["requests"]\n'
              '    takes = w["limits"]\n')
open(p, "w", encoding="utf-8").write(s)
PY
}

# init containers summed instead of maxed. Wrong in the OTHER
# direction, and that matters: a budget that over-reports gets
# switched off, and a switched-off budget is the same as none.
red_3() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('        ireq = max(ireq, _res_bytes(c.get("resources"), "requests"))\n'
              '        ilim = max(ilim, _res_bytes(c.get("resources"), "limits"))\n',
              '        ireq += _res_bytes(c.get("resources"), "requests")\n'
              '        ilim += _res_bytes(c.get("resources"), "limits")\n')
open(p, "w", encoding="utf-8").write(s)
PY
}

# the account measured against the whole machine instead of what is
# left after the human's floor: the comparison the desktop loses.
red_4() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('"reserves_fit": reserves <= r["allocatable_bytes"],',
              '"reserves_fit": reserves <= r["ram_total_bytes"],')
open(p, "w", encoding="utf-8").write(s)
PY
}

# the two verdicts collapsed into one. Whichever way it collapses, one
# of the two answers becomes a lie.
red_5() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('        "takes_fit": takes <= r["ram_total_bytes"],\n', "")
open(p, "w", encoding="utf-8").write(s)
PY
}

# and the check's own subject taken away: with the weighing renamed,
# finding no bad arithmetic must NOT be reported as everything fine.
red_6() {
    sed -i 's|^def _weigh_podspec(spec):|def _pesar_pod(spec):|' \
        "$AEGIS_ROOT/lib/aegis/host.py"
}

# control: PROSE that names `medium: Memory` without mounting one.
# This is the false positive the check produced in its first minute —
# the quota's comment now explains the tmpfs, and counting that would
# report three manifests where two mount it.
control_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/gateway.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("kind: Deployment",
              "# a legitimate note: this one mounts no emptyDir with\n"
              "# medium: Memory, unlike the two GPU engines.\nkind: Deployment", 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: one more term in the account, added the way the rule asks.
# Growing the arithmetic has to stay green.
control_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('        "reserves_bytes": reserves,',
              '        "hugepages_bytes": 0,\n        "reserves_bytes": reserves,')
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: an engine that legitimately stops mounting a tmpfs. The
# count is informational; the rules are about the arithmetic, and a
# manifest changing shape must not turn them red.
control_3() {
    sed -i 's|          emptyDir: {medium: Memory, sizeLimit: 1Gi}|          emptyDir: {sizeLimit: 1Gi}|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/ai-system/engine-mt.yaml"
}

# THE GPU LANE COUNTED ON A HOST THAT HAS NONE. The engines carry no
# `replicas:` in the seed -- born at zero, raised by the controller --
# and the first walk read "absent" as one. Measured 2026-09-10: 11 GiB
# of engines counted on a host that would never run them, which on a
# 16 GiB VPS with AI=cpu makes phase 87 refuse a valid install.
red_7() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('        return 0 if ai in ("cpu", "no") else 1\n', '        return 1\n')
open(p, "w", encoding="utf-8").write(s)
PY
}
