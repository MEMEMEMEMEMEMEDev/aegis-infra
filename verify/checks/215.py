"""Check 215 — what the update timer publishes is what the alerts read,
and the timer cannot act.

THREE JOINS THAT ROT IN DIFFERENT WAYS.

1. A rule that reads a series nobody publishes does not go red. It goes
   EMPTY, and an empty rule is indistinguishable from a healthy platform
   — which is the failure this whole product is written against, wearing
   its most convincing disguise. So every series the rules name has to
   be one the producer emits.

2. A series nobody reads is dead weight that looks like coverage. It is
   reported the other way round, and it is the softer of the two.

3. The timer must not be able to ACT. That is the operator's decision —
   aegis never opens an update window because a clock said so — and it
   is checked by reading what the unit actually runs, not by trusting
   the sentence in its description.

And one property of the family itself: the sibling that watches the
silence. Every rule here compares against a value, so every one goes
empty rather than false when the producer stops. Exactly one rule has to
be written on `absent()` for that.
"""
import os
import re
import subprocess
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []

UNIT = os.path.join(ROOT, "share", "systemd", "aegis-update-notice.service")
TIMER = os.path.join(ROOT, "share", "systemd", "aegis-update-notice.timer")
RULES = os.path.join(ROOT, "seed", "platform", "k8s", "base", "observability",
                     "rules", "vmalert-rules.yaml")
UPD = os.path.join(ROOT, "libexec", "aegis-update")

for f in (UNIT, TIMER, RULES, UPD):
    if not os.path.isfile(f):
        print(f"SCOPE: {os.path.relpath(f, ROOT)} is not there")
        sys.exit(0)

# ── what the producer emits, read by RUNNING it over the seed ────────
# Not by grepping for `emit(` — a name built out of a variable would
# slip past that, and a series that exists only when a branch is taken
# is exactly the one a rule would read as empty. The seed is used as the
# platform so this needs no instance and no network.
import json
import pathlib
import shutil
import tempfile


def _publish(home):
    env = {**os.environ, "AEGIS_ROOT": ROOT,
           "PLATFORM_DIR": os.path.join(ROOT, "seed", "platform"),
           "AEGIS_HOME": str(home), "AEGIS_CMD": "aegis"}
    # `--offline` on purpose: what is being joined is the SHAPE of the
    # exposition against the names the rules read, and that shape is the
    # same whether upstream answered or not. Without it every mutation
    # of this check's teeth would ask fifty public registries — thirty-
    # two of them in parallel — which is both slow and rude, and the
    # 429s it earned would make the check flaky about something it is
    # not even measuring.
    r = subprocess.run([sys.executable, UPD, "metrics", "--json", "--offline"],
                       capture_output=True, text=True, env=env, timeout=300)
    try:
        doc = json.loads(r.stdout)
    except ValueError:
        findings.append(f"`update metrics --json` returned no document (rc {r.returncode}): "
                        f"{(r.stdout or '')[:120]}{(r.stderr or '')[-200:]}")
        return set()
    exposition = ""
    for st in doc.get("steps", []):
        exposition = st.get("exposicion") or exposition
    return {ln.split("{")[0].split(" ")[0]
            for ln in exposition.splitlines() if ln and not ln.startswith("#")}


# BOTH BRANCHES OF THE PRODUCER, because the window series only exist
# once a window has closed — and a fixture that only ever ran the first
# branch would report half the family as «published by nobody». One
# throwaway home with no window at all, one with a journal in it.
tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-215-"))
published = set()
try:
    sys.path.insert(0, os.path.join(ROOT, "lib"))
    os.environ["AEGIS_ROOT"] = ROOT
    virgin = tmp / "virgin"
    virgin.mkdir()
    published |= _publish(virgin)
    used = tmp / "used"
    try:
        from aegis import window as _win
        j = _win.Journal("20260918T000000Z", used)
        j.open({"head": "a" * 40, "tree": "b" * 40}, note="check 215")
        j.note("commit", sha="c" * 40, subject="chore(update): a thing 1 → 2",
               pin="chart:thing", layer=4)
        j.close("accepted")
    except Exception as e:                                # noqa: BLE001
        findings.append(f"a window's journal could not be fabricated ({e}): the series "
                        f"that only exist after a window were not checked")
    published |= _publish(used)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

if not published:
    findings.append("the producer published NO series over the seed: every rule of the "
                    "family would read empty, and an empty rule looks exactly like a "
                    "platform with nothing to update")

# ── what the rules read ──────────────────────────────────────────────
rules_text = open(RULES, encoding="utf-8").read()
m = re.search(r"^  actualizaciones\.yaml: \|$(.*?)(?=^  \S+\.yaml: \||\Z)",
              rules_text, re.M | re.S)
if not m:
    findings.append("there is no `actualizaciones.yaml` group in the rules: what is "
                    "behind is measured and nobody is told")
    group = ""
else:
    group = m.group(1)
read = set(re.findall(r"\b(aegis_update_[a-z_]+)\b", group))
for name in sorted(read - published):
    findings.append(f"the alerts read {name!r} and the producer does not publish it: that "
                    f"rule does not go red, it goes EMPTY, which is indistinguishable "
                    f"from a healthy platform")
for name in sorted(published - read):
    findings.append(f"{name!r} is published and no alert reads it: a series nobody reads "
                    f"is dead weight that looks like coverage")

# ── the sibling that watches the silence ─────────────────────────────
if group and "absent(" not in group:
    findings.append("no rule of the family is written on `absent()`: every one of them "
                    "compares against a value, so when the producer stops they all go "
                    "empty and the panel stays calm")
alerts = re.findall(r"- alert: (\w+)", group)
if group and not alerts:
    findings.append("the group carries no alert at all")
for name in ("UpdateWindowDue", "UpdateMeasurementStopped"):
    if group and name not in alerts:
        findings.append(f"the family has no {name}: "
                        + ("nothing reminds anybody that a window is due"
                           if name == "UpdateWindowDue" else
                           "nothing notices when the measurement itself stops"))

# ── the timer notices; it must not be able to act ────────────────────
unit = open(UNIT, encoding="utf-8").read()
exec_lines = [ln for ln in unit.splitlines() if ln.startswith("ExecStart")]
if not exec_lines:
    findings.append("the unit runs nothing")
body = " ".join(exec_lines)
# The verbs that change something. Read out of the command itself so a
# verb added tomorrow is covered without editing this list.
# The verbs are read off the command's own header, which is the line
# `aegis` itself reads to build the menu. Asking `--help` needed an
# environment the check had already thrown away, and «I could not read
# the verbs» is not something to shrug at: it is the list that decides
# what the timer is forbidden to run.
verbs = set()
head = open(UPD, encoding="utf-8").read()
hm = re.search(r"^# aegis-subcommands:(.*)$", head, re.M)
if hm:
    verbs = set(hm.group(1).split())
READ_ONLY = {"inventory", "plan", "status", "metrics"}
if not verbs:
    findings.append("the verbs of `aegis update` could not be read, so what the timer is "
                    "allowed to run could not be checked")
for verb in sorted(verbs - READ_ONLY):
    if re.search(rf"\bupdate {verb}\b", body):
        findings.append(f"the notice unit runs `aegis update {verb}`, which CHANGES "
                        f"things. A clock does not open an update window: that is the "
                        f"operator's, and the unit exists to tell them, not to act")
if "--yes" in body:
    findings.append("the notice unit carries --yes: whatever it runs, it would act")
if re.search(r"\bupdate metrics\b", body) is None:
    findings.append("the notice unit does not run `aegis update metrics`: nothing "
                    "publishes the series the alerts read")

# ── and the timer is a timer, not a one-shot that can be missed ──────
timer = open(TIMER, encoding="utf-8").read()
if "OnCalendar" not in timer:
    findings.append("the timer has no OnCalendar: it would run once at boot and never again")
if "Persistent=true" not in timer:
    findings.append("the timer does not catch up a missed run: a laptop closed for four "
                    "days would simply not measure, and a stale count is worse than a "
                    "late one because the panel keeps showing the old number")

for f in findings:
    print(f)
print(f"SCOPE: {len(published)} series published against {len(read)} read by "
      f"{len(alerts)} alert(s), and the unit's own command line")
