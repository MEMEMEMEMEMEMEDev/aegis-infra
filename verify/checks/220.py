"""Check 220 — a window that dies leaves its page visible to somebody.

WITH A DATE ON IT: 2026-09-20. A window was killed outright while it
was measuring — the kind of death that carries no signal a process can
handle — so its exit trap never ran.

Three of the four things it had changed about the machine came back
anyway: the silences it raised EXPIRE on their own (which is exactly
why they are given an expiry), and Jenkins and the backup clock were
put back by other means. The maintenance page has no expiry. Five
public sites answered 503 until a human happened to look at them.

THE PROMISE THIS FIXES IN PLACE: the fact that a page is up survives
the process that raised it, is DERIVED from what the window wrote
rather than from a flag beside it, and reaches somebody who is not
staring at a terminal.

  1. the journal alone answers «is the page up», with no second marker
     that could disagree with it the morning after;
  2. `update status` says so, as a FAILURE, with the command to undo it
     — including when the window left no report at all, which is what a
     killed one leaves;
  3. the metrics carry it, so the alert family reaches the phone.

All of it driven over journals built here, with no cluster.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
os.environ["AEGIS_ROOT"] = ROOT
findings = []

UPD = os.path.join(ROOT, "libexec", "aegis-update")
try:
    from aegis import window as win
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/window.py cannot be imported ({e}): nothing was driven")
    print("SCOPE: nothing was driven")
    sys.exit(0)

if not hasattr(win.Journal, "page_is_up"):
    print("a journal cannot say whether the page it raised ever came down: a window "
          "killed outright leaves the operator's sites behind it with nothing to notice")
    print("SCOPE: nothing was driven")
    sys.exit(0)

tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-220-"))
driven = 0
try:
    def journal(home, wid, *hooks, close=None):
        j = win.Journal(wid, home)
        j.open({"head": "a" * 40, "tree": "b" * 40}, note="check 220")
        for hook, rc in hooks:
            j.note("maintenance", hook=hook, ran=True, rc=rc)
        if close:
            j.close(close)
        return j

    # ── 1: the journal alone answers it ─────────────────────────────
    cases = [
        ((("on", 0),), True),
        ((("on", 0), ("off", 0)), False),
        ((("on", 0), ("off", 1)), True),    # the hook FAILED: still up
        ((("on", 1),), False),              # it never went up
        ((), False),
        ((("on", 0), ("off", 0), ("on", 0)), True),   # raised again for a rollback
    ]
    for n, (hooks, want) in enumerate(cases):
        j = journal(tmp / f"h{n}", f"2026092{n}T000000Z", *hooks)
        driven += 1
        got = j.page_is_up()
        if got is not want:
            findings.append(f"a journal whose hooks were {list(hooks)} answers "
                            f"«page up = {got}» and it is {want}")

    # ── 2: `status` says so, and says it as a failure ───────────────
    home = tmp / "killed"
    journal(home, "20260920T090000Z", ("on", 0))          # no report: killed
    env = {**os.environ, "AEGIS_ROOT": ROOT, "AEGIS_HOME": str(home), "AEGIS_CMD": "aegis"}
    r = subprocess.run([sys.executable, UPD, "status", "--json"],
                       capture_output=True, text=True, env=env, timeout=120)
    driven += 1
    try:
        doc = json.loads(r.stdout)
    except ValueError:
        doc = {"steps": []}
        findings.append(f"`update status --json` returned no document about a killed "
                        f"window (rc {r.returncode}): {r.stdout[:150]}{r.stderr[-200:]}")
    left = [s for s in doc.get("steps", []) if s.get("step") == "window:page-left-up"]
    if not left:
        findings.append("`update status` says nothing about a window that raised the page "
                        "and left no report: that is exactly what a killed one leaves, and "
                        "the page is the one thing that does not expire on its own")
    elif left[0].get("state") != "wrong":
        findings.append(f"the page being left up is reported as {left[0].get('state')!r}: "
                        f"the operator's public sites may be behind it, which is not a note")
    elif not left[0].get("por_que"):
        findings.append("the page being left up is reported with no reason beside it")

    # and a window that took it down again says nothing
    home2 = tmp / "clean"
    journal(home2, "20260920T090000Z", ("on", 0), ("off", 0), close="accepted")
    env2 = {**env, "AEGIS_HOME": str(home2)}
    r2 = subprocess.run([sys.executable, UPD, "status", "--json"],
                        capture_output=True, text=True, env=env2, timeout=120)
    driven += 1
    try:
        doc2 = json.loads(r2.stdout)
    except ValueError:
        doc2 = {"steps": []}
        findings.append("`update status --json` returned no document about a clean window")
    if any(s.get("step") == "window:page-left-up" for s in doc2.get("steps", [])):
        findings.append("a window that recorded taking the page down is still reported as "
                        "having left it up: an alarm that cries every time is one nobody "
                        "reads")

    # ── 3: the metrics carry it ─────────────────────────────────────
    envm = {**env, "PLATFORM_DIR": os.path.join(ROOT, "seed", "platform")}
    rm = subprocess.run([sys.executable, UPD, "metrics", "--json", "--offline"],
                        capture_output=True, text=True, env=envm, timeout=300)
    driven += 1
    try:
        expo = ""
        for st in json.loads(rm.stdout).get("steps", []):
            expo = st.get("exposicion") or expo
    except ValueError:
        expo = ""
        findings.append("`update metrics --json` returned no document")
    line = [ln for ln in expo.splitlines()
            if ln.startswith("aegis_update_page_raised")]
    if not line:
        findings.append("the metrics do not carry whether a page was left up: the only "
                        "way anybody learns of it is by reading a terminal, and the whole "
                        "family exists so that they do not have to")
    elif not line[0].endswith(" 1"):
        findings.append(f"a window that left its page up publishes «{line[0]}»: the alert "
                        f"reads that series and would stay quiet")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# ── and an alert reads it ────────────────────────────────────────────
rules = os.path.join(ROOT, "seed", "platform", "k8s", "base", "observability",
                     "rules", "vmalert-rules.yaml")
if os.path.isfile(rules):
    body = open(rules, encoding="utf-8").read()
    if "aegis_update_page_raised" not in body:
        findings.append("no alert reads aegis_update_page_raised: the series is published "
                        "and nothing carries it to a phone")

for f in findings:
    print(f)
print(f"SCOPE: {driven} journal(s) and command run(s) driven, none of them touching a "
      f"cluster")
