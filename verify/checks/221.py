"""Check 221 — a window judges the world it actually made.

THREE MISTAKES, ALL FOUND BY RUNNING ONE, AND ALL THE SAME MISTAKE:
comparing against a world that is not the one the window is responsible
for.

  1. IT JUDGED WITH THE PAGE UP. The round measures the tenant sites
     through the edge, and the maintenance page lives at the edge, so
     with the page raised they stop answering. Compared against the
     PHOTO, the page doing its job reads as damage the window caused.
     The acceptance under the page has to be measured against a round
     taken WITH the page up and nothing else changed yet — which is
     what the plan meant by «acceptance at the origin», with the edge
     accepted afterwards once the page is down.

  2. IT JUDGED BEFORE THE CLUSTER SETTLED. A sync is a request, not an
     arrival. Layer 5 bumped seven images written by hand and asked
     ArgoCD to converge; `busybox` and `curl` are in the init
     containers of half the platform, so Jenkins was rolling while the
     round was being taken, and a Jenkins that is restarting has «no
     build at all» on every one of its fourteen jobs. The window called
     that damage. Nothing was wrong: it healed in four minutes.

  3. AND THE ROLLBACK DID NOT ROLL BACK. There are two ways a window
     ends red — a layer's own acceptance, and the global one — and only
     the first ever reverted. The second set the word «rolled-back» on
     a window that kept every commit it had made.

The three are read out of the source, because they are facts about
control flow and order rather than about values; what CAN be driven
here —the wait for the cluster— is driven.
"""
import ast
import os
import re
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
os.environ["AEGIS_ROOT"] = ROOT
findings = []

UPD = os.path.join(ROOT, "libexec", "aegis-update")
if not os.path.isfile(UPD):
    print("SCOPE: there is no aegis update")
    sys.exit(0)
src = open(UPD, encoding="utf-8").read()
code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))

try:
    from aegis import window as win
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/window.py cannot be imported ({e})")
    print("SCOPE: nothing was read")
    sys.exit(0)

# ── 1: the baseline ──────────────────────────────────────────────────
if "baseline" not in code:
    findings.append("the window has no baseline: with the maintenance page up, the round "
                    "reports the tenant sites as not answering, and compared against the "
                    "photo the page doing its job reads as damage the window caused")
else:
    # It must be taken when the page was raised, and the comparisons
    # must use it rather than the photo.
    if not re.search(r"if raised:.*?run_json\(\"check\"\)", code, re.S):
        findings.append("the baseline is not taken under the page: it has to be a round "
                        "with the page up and nothing else changed yet, or it is the "
                        "photo by another name")
    if "win.compare(baseline," not in code:
        findings.append("the global acceptance does not compare against the baseline")
    if 'last_doc = baseline' not in code:
        findings.append("the layers are not judged against the baseline either: the "
                        "first layer would answer for the page")
    if re.search(r'win\.compare\(before\["round"\]\["doc"\]', code):
        findings.append("something still compares against the PHOTO while the page is "
                        "up: that reads the page as damage")

# ── 2: a sync is a request, not an arrival ───────────────────────────
if not hasattr(win, "argo_all_settled"):
    findings.append("nothing waits for every Application to settle: a layer that syncs "
                    "and judges at once measures a cluster that is still rolling")
else:
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue
        body = ast.get_source_segment(src, node) or ""
        body = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
        if 'cli.run("sync"' not in body:
            continue
        if "argo_all_settled" not in body and "argo_settled" not in body:
            findings.append(f"{node.name}() asks ArgoCD to sync and never waits for it: "
                            f"a sync is a request, and the acceptance that follows "
                            f"measures a cluster in the middle of rolling")

# ── 3: both red endings actually revert ──────────────────────────────
undo = [n for n in ast.walk(ast.parse(src))
        if isinstance(n, ast.FunctionDef) and n.name == "_undo"]
if not undo:
    findings.append("there is no single way back: two endings that both mean «undo this» "
                    "are two chances for one of them to only say so")
else:
    body = ast.get_source_segment(src, undo[0]) or ""
    if "roll_back" not in body:
        findings.append("_undo() does not roll anything back")
    if "argo_all_settled" not in body:
        findings.append("_undo() does not wait for the cluster after reverting: a "
                        "rollback that reports «the tree came back» while the cluster is "
                        "still rolling has measured nothing")
    calls = len(re.findall(r"=\s*_undo\(", code))
    if calls < 2:
        findings.append(f"_undo() is called from {calls} place(s): a window ends red in "
                        f"two ways —a layer's acceptance and the global one— and until "
                        f"2026-09-20 only the first of them reverted")
# and nothing may set the outcome to rolled-back without going through it
for m in re.finditer(r'outcome\s*=\s*"rolled-back"', code):
    line = code[:m.start()].count("\n") + 1
    findings.append(f"line {line} sets the outcome to «rolled-back» directly: the name of "
                    f"a thing is not the thing, and that is exactly how a window came to "
                    f"report a rollback it had not performed")

# ── the wait itself, driven against a fake kubectl ───────────────────
import shutil
import tempfile
import pathlib as _pl

tmp = _pl.Path(tempfile.mkdtemp(prefix="aegis-221-"))
driven = 0
try:
    fake = tmp / "kubectl"
    fake.write_text("#!/bin/sh\nprintf 'uno|Synced|Healthy\\ndos|OutOfSync|Healthy\\n'\n",
                    encoding="utf-8")
    fake.chmod(0o755)
    os.environ["PATH"] = f"{tmp}:{os.environ['PATH']}"
    r = win.argo_all_settled(timeout=1, poll=1)
    driven += 1
    if r.get("asentado") is not False:
        findings.append(f"an app that never reaches Synced was reported as "
                        f"{r.get('asentado')!r}: a wait that ran out is a failure, never "
                        f"a «probably fine»")
    fake.write_text("#!/bin/sh\nprintf 'uno|Synced|Healthy\\n'\n", encoding="utf-8")
    r2 = win.argo_all_settled(timeout=5, poll=1)
    driven += 1
    if r2.get("asentado") is not True:
        findings.append(f"a cluster where everything is Synced+Healthy came back "
                        f"{r2.get('asentado')!r}")
    fake.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    r3 = win.argo_all_settled(timeout=5, poll=1)
    driven += 1
    if r3.get("asentado") is not None:
        findings.append(f"a kubectl that could not answer came back {r3.get('asentado')!r} "
                        f"instead of «nobody could look»")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

for f in findings:
    print(f)
print(f"SCOPE: the baseline, the wait and the two red endings read out of the window, and "
      f"{driven} wait(s) driven against a kubectl that says what this check wants")
