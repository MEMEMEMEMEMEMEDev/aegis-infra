"""Check 214 — everything a window changes about the MACHINE is put back,
on every way out.

THE THREE THINGS NOBODY WOULD NOTICE. A window quiets Jenkins, silences
the alerts about the public sites, and stops the backup clock. All three
are right while it runs and all three are silent damage afterwards: an
instance that builds nothing, is deaf about its sites, and has no
backups — and not one of them announces itself. The alert that would
have told you about the sites is the one that was silenced.

So the way back is not «at the end»: it is a stack, pushed BEFORE each
change is made, and run in the exit path of every ending there is —
accepted, rolled back, needs-a-human, an exception nobody predicted.

Four properties, driven against the real Restore:

  1. what is pushed is undone, and in the reverse order it was made;
  2. it runs even when the window's body raised;
  3. one undo that FAILS does not stop the others, and is reported as
     failed rather than swallowed;
  4. the stack is empty afterwards, so a second pass cannot undo twice.

And one property of the window itself, read from its source because it
is about control flow and not about values: the restore runs in a
`finally`. A restore reachable only on the happy path is the one that
will not run on the day it matters.
"""
import os
import re
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
os.environ["AEGIS_ROOT"] = ROOT
findings = []

try:
    from aegis import window as win
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/window.py cannot be imported ({e}): the way back was not exercised")
    print("SCOPE: nothing was exercised")
    sys.exit(0)

# ── 1: reverse order ─────────────────────────────────────────────────
order = []
r = win.Restore()
r.push("first", lambda: order.append("first"), "a")
r.push("second", lambda: order.append("second"), "b")
r.push("third", lambda: order.append("third"), "c")
done = r.run()
if order != ["third", "second", "first"]:
    findings.append(f"the restore does not undo in the reverse order it was built: "
                    f"{order}. Two changes that depend on each other only come back in "
                    f"the reverse of the order they were made")
if len(done) != 3 or not all(d["ok"] for d in done):
    findings.append(f"three undos were pushed and the report says {done}")
if len(r) != 0:
    findings.append("the stack is not empty after running: a second pass would undo "
                    "everything twice")

# ── 2: it survives the body raising ──────────────────────────────────
ran = []
r2 = win.Restore()
r2.push("quiet", lambda: ran.append("quiet"), "Jenkins takes builds again")
try:
    try:
        raise RuntimeError("the window died between two layers")
    finally:
        r2.run()
except RuntimeError:
    pass
if ran != ["quiet"]:
    findings.append("the restore did not run when the body raised, which is the one "
                    "ending it exists for")

# ── 3: one failure does not stop the rest ────────────────────────────
reached = []


def _explodes():
    raise OSError("systemctl is not there")


r3 = win.Restore()
# The one that fails is pushed LAST, so it is the FIRST one popped. A
# fixture where the failure comes last proves nothing: returning early
# after the last item is indistinguishable from finishing.
r3.push("silences", lambda: reached.append("silences"), "the alerts speak again")
r3.push("quiet", lambda: reached.append("quiet"), "builds again")
r3.push("timer", _explodes, "the clock runs again")
out3 = r3.run()
if set(reached) != {"silences", "quiet"}:
    findings.append(f"an undo that failed stopped the others: only {reached} ran. Tidiness "
                    f"is not worth leaving the rest of the machine as the window left it")
failed = [d for d in out3 if not d["ok"]]
if len(failed) != 1 or "systemctl" not in failed[0].get("error", ""):
    findings.append(f"an undo that raised was not reported as failed: {out3}")
if any(d["ok"] for d in out3 if d["restored"] == "timer"):
    findings.append("an undo that raised was reported as done")

# ── the window runs it in a finally, and the page does NOT come down
#    after a red ───────────────────────────────────────────────────────
upd = open(os.path.join(ROOT, "libexec", "aegis-update"), encoding="utf-8").read()
code = "\n".join(ln for ln in upd.splitlines() if not ln.lstrip().startswith("#"))
m = re.search(r"\n    finally:\n(.*?)\n    steps\.finish\(\)", code, re.S)
if not m:
    findings.append("the window has no `finally` before it finishes: whatever it puts "
                    "back, it puts back only on the endings somebody thought of")
elif "restore.run()" not in m.group(1):
    findings.append("the restore stack is not run in the window's `finally`: it would be "
                    "skipped on exactly the ending it exists for")
if "restore.push" not in code:
    findings.append("nothing is ever pushed onto the restore stack: the window changes "
                    "things about the machine and records no way back")

# The page is the one thing that must NOT come back automatically after
# a red. A broken instance put back in front of the public is the moment
# the page exists for.
if not re.search(r'if outcome in \("accepted", "refused"\)', code):
    findings.append("the maintenance page comes down without asking what the outcome "
                    "was: after a red that puts a broken instance back in front of the "
                    "public, which is the one moment the page exists for")

# The heartbeat is never silenced, and that is a value, not a comment.
if "DeadmanAegis" in win.SILENCEABLE:
    findings.append("the window silences the heartbeat: that is the alert that fires "
                    "when the alerting itself stops working, and a window is when it "
                    "would be easiest to miss")
for name in win.NEVER_SILENCED:
    if name in win.SILENCEABLE:
        findings.append(f"{name} is in both lists: the one that says «never» loses")

for f in findings:
    print(f)
print(f"SCOPE: {len(done) + len(out3) + 1} undo(s) driven, including one that fails and "
      f"one body that raises; {len(win.SILENCEABLE)} alert(s) silenceable, "
      f"{len(win.NEVER_SILENCED)} never")
