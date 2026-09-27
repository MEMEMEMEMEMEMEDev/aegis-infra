"""Check 252 — a base run builds a member on the siblings it just built.

MEASURED 2026-09-23 on the cloud instance (plan/18 §5, finding 14):
phase 80 fires base-images with every member; php's Containerfile takes
its nginx `FROM …/aegis-base-nginx:3.22-000009@sha256:4329e1…`, the
house's build 9, shipped in the seed. In a clean registry that digest
does not exist: php died MANIFEST_UNKNOWN on build #3, and only the
propagation of the nginx just built fixed the pin, for build #4. A
clean install needed two passes, and the second one only happened
because a harmless line was read as a network failure (finding 13).

The class: a member of the run that stands on another member of the
same run. It is built after it, and on what THIS run built for it.
siblings.sh does both and is RUN here against a copy of the seed —
the order it prints and the Containerfile it leaves — and the
Jenkinsfile has to call it where it counts: `order` gives the list the
build loop walks, `pin` runs before kaniko.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
BI = os.path.join(ROOT, "seed", "platform", "base-images")
SIB = os.path.join(BI, "siblings.sh")
JF = os.path.join(BI, "Jenkinsfile")
findings = []

for f in (SIB, JF):
    if not os.path.isfile(f):
        print(f"{os.path.relpath(f, ROOT)} is missing: nothing resolves a member's siblings")
        sys.exit(0)

FROM_SIB = re.compile(r"^\s*FROM\s+(?:\S*/)?aegis-base-([a-z0-9-]+)[:@]", re.M)


def siblings(tree, m):
    with open(os.path.join(tree, m, "Containerfile"), encoding="utf-8") as f:
        return sorted(set(FROM_SIB.findall(f.read())))


def run(tree, *args, env=None):
    e = {"PATH": os.environ["PATH"]}
    e.update(env or {})
    p = subprocess.run(["sh", os.path.join(tree, "siblings.sh"), *args],
                       capture_output=True, text=True, env=e, timeout=30)
    return p.returncode, p.stdout, p.stderr


members = sorted(d for d in os.listdir(BI)
                 if os.path.isfile(os.path.join(BI, d, "Containerfile")))
pairs = [(m, s) for m in members for s in siblings(BI, m) if s in members]
if not pairs:
    print(f"SCOPE: no member of the seed stands on another ({' '.join(members)}) — nothing to order yet")
    sys.exit(0)

DIG = "sha256:" + "a" * 64
with tempfile.TemporaryDirectory() as tmp:
    tree = os.path.join(tmp, "base-images")
    shutil.copytree(BI, tree)

    # ── 1. the order: every member after the siblings it stands on ─────
    # asked in REVERSE, the order a caller that does not know would use
    asked = list(reversed(members))
    rc, out, err = run(tree, "order", *asked)
    got = out.split()
    if rc != 0:
        findings.append(f"`siblings.sh order {' '.join(asked)}` fails (rc {rc}): {err.strip()[:160]}")
    elif sorted(got) != sorted(asked):
        findings.append(f"`siblings.sh order` loses or invents members: asked {asked}, got {got}")
    else:
        for m, s in pairs:
            if got.index(s) > got.index(m):
                findings.append(f"`siblings.sh order` puts {m} before {s}, which it stands on: "
                                f"{m} is built on a pin this run has not produced")

    # ── 2. the pin: rewritten to what this run built, one line each ────
    for m, s in pairs:
        cf = os.path.join(tree, m, "Containerfile")
        with open(cf, encoding="utf-8") as f:
            before = f.read()
        tag = "9.99-424242"
        rc, out, err = run(tree, "pin", m, env={"RUN_MEMBERS": f"{s} {m}",
                                                "BUILT_REFS": f"{s}={tag}@{DIG}"})
        with open(cf, encoding="utf-8") as f:
            after = f.read()
        changed = [(a, b) for a, b in zip(before.splitlines(), after.splitlines()) if a != b]
        if rc != 0:
            findings.append(f"`siblings.sh pin {m}` with {s} built fails (rc {rc}): {err.strip()[:160]}")
        elif not re.search(rf"^\s*FROM\s+\S*aegis-base-{s}:{re.escape(tag)}@{DIG}\b", after, re.M):
            findings.append(f"`siblings.sh pin {m}` leaves {m}'s FROM on the shipped pin of {s}: "
                            f"in a clean registry that digest does not exist (MANIFEST_UNKNOWN, build #3)")
        elif len(before.splitlines()) != len(after.splitlines()) or len(changed) != len(FROM_SIB.findall(before)):
            findings.append(f"`siblings.sh pin {m}` touches more than its FROM lines ({len(changed)} changed)")
        with open(cf, "w", encoding="utf-8") as f:
            f.write(before)

        # a sibling that failed stops the member, by name
        rc, out, err = run(tree, "pin", m, env={"RUN_MEMBERS": f"{s} {m}", "FAILED_NOW": s})
        if rc == 0:
            findings.append(f"`siblings.sh pin {m}` goes on when {s} FAILED in the run: {m} would be "
                            f"built on the shipped pin and die MANIFEST_UNKNOWN deep in kaniko")
        elif s not in err or "FAILED" not in err:
            findings.append(f"`siblings.sh pin {m}` refuses a failed {s} without saying it failed "
                            f"(the log would blame the order): {err.strip()[:120]}")
        # in the run, not built yet: the order was broken
        rc, out, err = run(tree, "pin", m, env={"RUN_MEMBERS": f"{s} {m}"})
        if rc == 0:
            findings.append(f"`siblings.sh pin {m}` goes on when {s} is in the run and not built yet")
        with open(cf, "w", encoding="utf-8") as f:
            f.write(before)
        # not in the run: the shipped pin stays, and that is correct
        rc, out, err = run(tree, "pin", m, env={"RUN_MEMBERS": m})
        with open(cf, encoding="utf-8") as f:
            kept = f.read()
        if rc != 0 or kept != before:
            findings.append(f"`siblings.sh pin {m}` with {s} outside the run does not leave the "
                            f"Containerfile alone (rc {rc})")

    # ── 3. a cycle is an error, not an order ───────────────────────────
    for a, b in (("zz-a", "zz-b"), ("zz-b", "zz-a")):
        os.makedirs(os.path.join(tree, a))
        with open(os.path.join(tree, a, "Containerfile"), "w", encoding="utf-8") as f:
            f.write(f"FROM r/aegis-base-{b}:1@{DIG}\n")
    rc, out, err = run(tree, "order", "zz-a", "zz-b")
    if rc == 0:
        findings.append(f"`siblings.sh order` accepts two members that stand on each other: printed {out.split()}")

# ── 4. the Jenkinsfile calls it where it counts ────────────────────────
with open(JF, encoding="utf-8") as f:
    jf = "\n".join(ln for ln in f.read().splitlines() if not re.match(r"^\s*//", ln))
stage = re.search(r"stage\('members'\)\s*\{(.*?)\n    stage\('", jf, re.S)
mbody = stage.group(1) if stage else ""
o = re.search(r"def\s+(\w+)\s*=\s*sh\([^)]*siblings\.sh order \$RUN_MEMBERS", mbody, re.S)
if not o:
    findings.append("stage('members') never asks siblings.sh for the order: the loop walks MEMBERS as "
                    "asked, and php is built before the nginx it stands on")
elif not re.search(rf"^\s*MEMBERS_TO_BUILD\s*=\s*{o.group(1)}\s*$", mbody, re.M):
    findings.append(f"stage('members') computes the order ({o.group(1)}) and builds another list")
elif not re.search(r"env\.RUN_MEMBERS\s*=\s*members\.join", mbody):
    findings.append("stage('members') does not put the run's members in env.RUN_MEMBERS: "
                    "siblings.sh cannot tell a sibling of the run from one outside it")
build = re.search(r"stage\('build'\)\s*\{(.*?)\n    stage\('", jf, re.S)
bbody = build.group(1) if build else ""
i_pin = bbody.find("siblings.sh pin")
i_kan = bbody.find("/kaniko/executor")
if i_pin == -1:
    findings.append("stage('build') never pins a member's siblings: php is built on the seed's pin, "
                    "which does not exist in a clean registry (finding 14)")
elif i_kan == -1 or i_pin > i_kan:
    findings.append("stage('build') pins the siblings after kaniko has built on the old pin")
else:
    head = bbody[:i_pin]
    for var, src in (("BUILT_REFS", "built"), ("FAILED_NOW", "failed")):
        if not re.search(rf"env\.{var}\s*=\s*{src}\.", head):
            findings.append(f"stage('build') calls siblings.sh pin without env.{var} from `{src}`: "
                            f"it cannot tell what this run built or lost")

print(f"SCOPE: {len(pairs)} member(s) standing on a sibling ({', '.join(f'{m} on {s}' for m, s in pairs)}); "
      f"order, pin, a failed sibling, a sibling not yet built, one outside the run, and a cycle exercised")
for f in findings:
    print(f)
