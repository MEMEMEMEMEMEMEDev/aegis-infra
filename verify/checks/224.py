"""Check 224 — the clocks are installed by a phase, and a clock is a next run.

Read out of the source, and driven where it can be: the helper that
reads a timer's next appointment is exercised against a fake
`systemctl` that answers the four shapes systemd produces, because the
whole class of bug is a reader that takes «active» for «scheduled».
"""
import os
import re
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
findings = []
driven = 0


def nc(path):
    with open(path, encoding="utf-8") as f:
        return "\n".join(ln for ln in f.read().splitlines()
                         if not re.match(r"^\s*#", ln))


PH = os.path.join(ROOT, "init", "phases", "05-host.sh")
LIB = os.path.join(ROOT, "lib", "systemd.sh")
COMMON = os.path.join(ROOT, "lib", "common.sh")
CHECK = os.path.join(ROOT, "libexec", "aegis-check")
WIN = os.path.join(ROOT, "lib", "aegis", "window.py")
TIMER = os.path.join(ROOT, "share", "systemd", "aegis-backup.timer")
UNITS = ("aegis-backup", "aegis-host-metrics", "aegis-update-notice")
for f in (PH, LIB, COMMON, CHECK, WIN, TIMER):
    if not os.path.isfile(f):
        findings.append(f"{os.path.relpath(f, ROOT)} is missing")
if findings:
    for f in findings:
        print(f)
    print("SCOPE: files missing")
    sys.exit(0)

ph = nc(PH)
# ── 1. the phase installs the three, derives backup.env, enables linger ──
for u in UNITS:
    if not os.path.isfile(os.path.join(ROOT, "share", "systemd", f"{u}.timer")):
        findings.append(f"share/systemd/{u}.timer is not shipped")
    if u not in ph:
        findings.append(f"phase 05 never names {u}: that clock is left for a README")
if not re.search(r"install\s+-m\s+644\s+\"\$AEGIS_ROOT/share/systemd/\$_c\.service\"", ph):
    findings.append("phase 05 does not install the units from share/systemd into the user's units")
if "systemctl --user enable --now" not in ph:
    findings.append("phase 05 does not enable the timers: installed and asleep")
if not re.search(r"^\s*run_cmd\s+sudo\s+loginctl\s+enable-linger", ph, re.M):
    findings.append("phase 05 does not enable linger: the clocks stop when the operator logs out")
if "backup.env" not in ph or "SOPS_AGE_KEY_FILE=" not in ph:
    findings.append("phase 05 does not derive backup.env with the key's path: the service starts with "
                    "no profile and the capture cannot open the store")
if not re.search(r"^\s*run_cmd\s+sudo\s+ln\s+-sfn\s+\"\$AEGIS_ROOT/share\"\s+/usr/local/share/aegis", ph, re.M):
    findings.append("phase 05 does not put share/ where the units and two protocols say it is "
                    "(/usr/local/share/aegis)")
if "timer_next_elapse" not in ph:
    findings.append("phase 05 gates on «enabled» and never on a next run")
# anchored on code, not on a comment: nc() strips the comments
tail = ph.split("CLOCKS=(", 1)[1] if "CLOCKS=(" in ph else ""
if "gate_red" not in tail[:4000]:
    findings.append("phase 05 says nothing when there is no user session bus: the clocks would be "
                    "silently skipped")

# ── 2. the backup timer has a calendar ──────────────────────────────
tm = nc(TIMER)
if not re.search(r"^OnCalendar=", tm, re.M):
    findings.append("aegis-backup.timer has no OnCalendar: a restart leaves it with no next run "
                    "until the service happens to run, which it never does")
if not re.search(r"^OnUnitActiveSec=", tm, re.M):
    findings.append("aegis-backup.timer lost its interval: the cadence door of `data remote cadence` "
                    "has nothing to shorten")

# ── 3. one helper, and every reader uses it ─────────────────────────
lib = nc(LIB)
if "timer_next_elapse()" not in lib:
    findings.append("lib/systemd.sh does not define timer_next_elapse")
if "lib/systemd.sh" not in nc(COMMON):
    findings.append("common.sh does not source lib/systemd.sh: the phases have no reading of a next run")
chk = nc(CHECK)
if "lib/systemd.sh" not in chk or not re.search(r"\btimer_next_elapse\s+--user\s+", chk):
    findings.append("the round never asks the clocks for a next run: a fresh bundle today says nothing "
                    "about tomorrow")
for u in UNITS:
    if u not in chk:
        findings.append(f"the round does not read {u}.timer")
win = nc(WIN)
m = re.search(r"def timer_start\(.*?\n(?=\n\n|\ndef )", win, re.S)
if not m or "timer_next_elapse" not in m.group(0):
    findings.append("window.timer_start puts the timer back and never reads a next run: the restore "
                    "reports a clock that will not fire (error nº 13)")

# ── 4. the helper, driven against the four shapes systemd produces ──
with tempfile.TemporaryDirectory() as td:
    fake = os.path.join(td, "systemctl")
    cases = {
        # (realtime, monotonic) -> expected rc, printed
        ("Mon 2026-09-21 00:17:16 -03", "infinity"): (0, "Mon 2026-09-21 00:17:16 -03"),
        ("", "15h 25min"): (0, "15h 25min"),
        ("", "infinity"): (1, ""),
        ("", ""): (1, ""),
    }
    for (rt, mono), (want_rc, want_out) in cases.items():
        with open(fake, "w") as f:
            f.write("#!/usr/bin/env bash\n"
                    "case \"$*\" in\n"
                    f"  *NextElapseUSecRealtime*) printf '%s\\n' '{rt}' ;;\n"
                    f"  *NextElapseUSecMonotonic*) printf '%s\\n' '{mono}' ;;\n"
                    "  *) exit 2 ;;\n"
                    "esac\n")
        os.chmod(fake, stat.S_IRWXU)
        r = subprocess.run(["bash", "-c", f"source '{LIB}'; timer_next_elapse --user x.timer"],
                           capture_output=True, text=True,
                           env={**os.environ, "PATH": td + ":" + os.environ.get("PATH", "")})
        driven += 1
        got = (r.stdout or "").strip()
        if r.returncode != want_rc or got != want_out:
            findings.append(f"timer_next_elapse with realtime={rt!r} monotonic={mono!r} answered "
                            f"rc {r.returncode} {got!r}, expected rc {want_rc} {want_out!r}: "
                            f"{'«active» taken for «scheduled»' if want_rc == 1 else 'a real appointment reported as none'}")

for f in findings:
    print(f)
print(f"SCOPE: the phase, the unit, the round and the window read; the helper driven {driven} times "
      f"against a systemctl that answers what this check wants")
