"""Check 212 — the record of a window names every commit it made.

WHY A COUNT IS NOT A RECORD. The one question asked about a window is
asked afterwards and by somebody who was not there: what did it change.
A report that says «four commits» answers nothing — the person reading
it at midnight needs the four shas, because the next thing they do is
look at one of them or revert it by hand. `aegis update status` is the
only place that answer lives, and a journal whose entries never reach
the report is a record that exists and cannot be read.

Three properties:
  1. the report names every commit of the journal, by sha;
  2. `update status` hands those shas out, through the document, to
     whatever reads it;
  3. a window that made no commit says a MEASURED zero — the command
     answers «that window changed nothing», never silence.
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
findings = []

UPD = os.path.join(ROOT, "libexec", "aegis-update")
if not os.path.isfile(UPD):
    print("SCOPE: there is no aegis update")
    sys.exit(0)
try:
    from aegis import window as win
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/window.py cannot be imported ({e}): no journal was written")
    print("SCOPE: nothing was exercised")
    sys.exit(0)

tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-212-"))
try:
    home = tmp / "home"
    SHAS = ["0123456789abcdef0123456789abcdef01234567",
            "89abcdef0123456789abcdef0123456789abcdef",
            "fedcba9876543210fedcba9876543210fedcba98"]
    j = win.Journal("20260918T000000Z", home)
    j.open({"head": SHAS[0], "tree": "t" * 40}, note="check 212")
    for i, sha in enumerate(SHAS, 1):
        j.note("commit", sha=sha, subject=f"chore(update): thing {i} a → b",
               pin=f"chart:thing{i}", layer=4)
    report = j.close("accepted", comparacion={"nuevos": [], "cegados": []})

    # ── 1: the report names them ─────────────────────────────────────
    named = {c.get("sha") for c in report.get("commits", [])}
    for sha in SHAS:
        if sha not in named:
            findings.append(f"the report of a window does not name the commit {sha[:12]} "
                            f"that its own journal recorded: a record that cannot be read "
                            f"is not a record")
    for c in report.get("commits", []):
        if not c.get("subject"):
            findings.append(f"the commit {c.get('sha', '?')[:12]} is named with no subject: "
                            f"a sha with nothing beside it makes the reader open git to "
                            f"find out what a window did")

    # ── 2: `status` hands them out ───────────────────────────────────
    env = {**os.environ, "AEGIS_ROOT": ROOT, "AEGIS_HOME": str(home)}
    r = subprocess.run([sys.executable, UPD, "status", "--json"],
                       capture_output=True, text=True, env=env, timeout=120)
    try:
        doc = json.loads(r.stdout)
    except ValueError:
        doc = None
        findings.append(f"`update status --json` did not return a document "
                        f"(rc {r.returncode}): {r.stdout[:200]}{r.stderr[-200:]}")
    if doc is not None:
        flat = json.dumps(doc, ensure_ascii=False)
        for sha in SHAS:
            if sha not in flat:
                findings.append(f"`update status --json` does not carry the commit "
                                f"{sha[:12]}: the report has it and the command drops it "
                                f"on the way out")
        if doc.get("rc") != 0:
            findings.append(f"`status` about an accepted window exited {doc.get('rc')}")

    # ── 3: a window that changed nothing says a measured zero ────────
    home2 = tmp / "home2"
    j2 = win.Journal("20260918T010000Z", home2)
    j2.open({"head": "x" * 40, "tree": "y" * 40}, note="check 212, empty")
    rep2 = j2.close("accepted")
    if rep2.get("commits") != []:
        findings.append("a window that made no commit reports commits it never made")
    env2 = {**os.environ, "AEGIS_ROOT": ROOT, "AEGIS_HOME": str(home2)}
    r2 = subprocess.run([sys.executable, UPD, "status", "--json"],
                        capture_output=True, text=True, env=env2, timeout=120)
    try:
        doc2 = json.loads(r2.stdout)
    except ValueError:
        doc2 = {"steps": []}
        findings.append("`update status --json` returned no document about an empty window")
    if not doc2.get("steps"):
        findings.append("`update status` about a window that changed nothing said nothing: "
                        "a measured zero and a silence have to look different")

    # ── and an instance that has never opened one ────────────────────
    home3 = tmp / "home3"
    home3.mkdir(parents=True)
    env3 = {**os.environ, "AEGIS_ROOT": ROOT, "AEGIS_HOME": str(home3)}
    r3 = subprocess.run([sys.executable, UPD, "status", "--json"],
                        capture_output=True, text=True, env=env3, timeout=120)
    try:
        doc3 = json.loads(r3.stdout)
    except ValueError:
        doc3 = {}
        findings.append("`update status --json` returned no document on an instance that "
                        "has never opened a window")
    if doc3.get("rc") not in (0, None):
        findings.append(f"an instance that has never opened a window is not an error, and "
                        f"`status` exited {doc3.get('rc')}")
    if doc3 and not doc3.get("steps"):
        findings.append("`status` on an instance with no window emitted no step: zero "
                        "windows is a measurement, and zero steps is rc 2 by the house "
                        "contract")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

for f in findings:
    print(f)
print(f"SCOPE: a journal of {len(SHAS)} commit(s), an empty one and an instance with no "
      f"window at all, each read back through `update status --json`")
