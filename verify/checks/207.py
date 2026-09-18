"""Check 207 — a window's commits come back, one by one, to the same tree.

THE PROMISE BEING TESTED. A window is allowed to change the platform
because everything it does can be undone without a human. That promise
is worth exactly what it has been exercised at, and exercising it on
the live instance means breaking the live instance on purpose. So it is
exercised here, on a real copy of the seed's platform in a throwaway
directory, with the very same functions the window calls: no mock, no
second implementation, no «this is roughly what it would do».

Five properties, and each one is a way the way back has failed in real
systems:

  1. the edits land where the inventory said, and nowhere else;
  2. the commits carry ONLY the files the window wrote — work that was
     already in the tree must not ride into a commit that a rollback
     then reverts;
  3. reverting newest first brings the tree back byte for byte;
  4. a commit that does NOT revert cleanly stops the walk and says so,
     instead of leaving a tree nobody described;
  5. an edit whose line no longer reads the way the inventory said is
     REFUSED, rather than written blind.
"""
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

try:
    from aegis import pins, window as win
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/window.py cannot be imported ({e}): the way back was not exercised")
    print("SCOPE: nothing was exercised")
    sys.exit(0)

SEED = pathlib.Path(ROOT) / "seed" / "platform"
if not SEED.is_dir():
    print("SCOPE: there is no seed platform to copy")
    sys.exit(0)


def git(root, *a, check=True):
    r = subprocess.run(["git", "-C", str(root), *a], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(a)}: {r.stderr.strip()[:200]}")
    return r.stdout.rstrip("\n")


tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-207-"))
try:
    plat = tmp / "platform"
    shutil.copytree(SEED, plat)
    git(plat, "init", "-q", "-b", "main")
    git(plat, "config", "user.email", "check207@aegis.invalid")
    git(plat, "config", "user.name", "check 207")
    git(plat, "add", "-A")
    git(plat, "commit", "-qm", "the tree as the seed ships it")
    origin_tree = win.tree_hash(plat)

    all_pins = pins.read(str(plat))
    # Three classes, so the exercise is not one file's shape: the host's
    # pins, a chart and an image written by hand. Whatever this tree
    # happens to carry — the classes are asked for, never assumed.
    picked = []
    for cls in ("userland", "chart", "raw-image", "mirror"):
        cand = [p for p in all_pins.values() if p.cls == cls and p.current]
        if cand:
            picked.append(sorted(cand, key=lambda p: p.name)[0])
    if len(picked) < 2:
        findings.append("fewer than two classes of pin could be picked out of the seed: "
                        "the way back was exercised on too little to mean anything")

    # ── (1) and (2): the edits, and what the commits carry ───────────
    home = tmp / "home"
    j = win.Journal("exercise", home)
    j.open({"tree": origin_tree, "head": win.head(plat)}, note="check 207")
    # Somebody else's work, already in the tree and NOT the window's:
    stray = plat / "NOTA-DEL-OPERADOR.txt"
    stray.write_text("work that was here before the window\n", encoding="utf-8")
    stray_before = stray.read_text(encoding="utf-8")

    for pin in picked:
        old = pin.current
        new = old + "-t207"
        try:
            files = win.rewrite(plat, pin, version=new)
        except win.RefusedEdit as e:
            findings.append(f"the edit of {pin.key} was refused on a tree that carries it: {e}")
            continue
        sha = win.commit(plat, files, win.subject(pin, old, new))
        j.note("commit", sha=sha, subject=win.subject(pin, old, new), pin=pin.key, layer=0)
        carried = git(plat, "show", "--name-only", "--format=", sha).split()
        extra = [c for c in carried if c not in files]
        if extra:
            findings.append(f"the commit for {pin.key} carried files the window did not "
                            f"write: {extra[:4]} — a rollback would revert somebody "
                            f"else's work")

    if stray.is_file() and stray.read_text(encoding="utf-8") != stray_before:
        findings.append("the window's commits changed a file it never wrote")

    # The same pin twice, so the ORDER of the way back is what is being
    # tested and not merely the fact of reverting. Reverted oldest
    # first, the second of these conflicts.
    if picked:
        pin = pins.read(str(plat))[(picked[0].cls, picked[0].name)]
        old, new = pin.current, picked[0].current + "-t207bis"
        files = win.rewrite(plat, pin, version=new)
        sha = win.commit(plat, files, win.subject(pin, old, new))
        j.note("commit", sha=sha, subject=win.subject(pin, old, new), pin=pin.key, layer=0)

    made = len(j.commits())
    if made < 2:
        findings.append(f"only {made} commit(s) were made: the way back was not exercised "
                        f"on a sequence, and a sequence is the only thing order can go "
                        f"wrong in")

    # ── (3) the way back ─────────────────────────────────────────────
    r = win.roll_back(j, platform=plat, narrate=False)
    if r["atascado"]:
        findings.append(f"a commit of the window did not revert cleanly: "
                        f"{r['atascado'].get('por_que', '')[:160]}")
    if len(r["deshechos"]) != made:
        findings.append(f"{made} commit(s) were made and {len(r['deshechos'])} came back")
    same = win.came_back_to(j, platform=plat)
    if same.get("igual") is not True:
        findings.append(f"after reverting every commit the tree is NOT what the photo "
                        f"saw: {same}")
    if stray.is_file() and stray.read_text(encoding="utf-8") != stray_before:
        findings.append("the rollback changed a file the window never wrote")

    # ── (4) a commit that does not revert cleanly stops the walk ─────
    if picked:
        j2 = win.Journal("conflict", home)
        j2.open({"tree": win.tree_hash(plat), "head": win.head(plat)}, note="check 207")
        pin = pins.read(str(plat))[(picked[0].cls, picked[0].name)]
        files = win.rewrite(plat, pin, version=pin.current + "-a")
        sha = win.commit(plat, files, "chore(update): a")
        j2.note("commit", sha=sha, subject="chore(update): a", pin=pin.key, layer=0)
        # Somebody edits the same line outside the window. Reverting the
        # commit above can no longer apply.
        f = plat / files[0]
        body = f.read_text(encoding="utf-8").replace(pin.current + "-a", "edited-by-a-human")
        f.write_text(body, encoding="utf-8")
        git(plat, "commit", "-qam", "a human edited the same line")
        r2 = win.roll_back(j2, platform=plat, narrate=False)
        if not r2["atascado"]:
            findings.append("a commit that cannot be reverted was reported as reverted: "
                            "the walk has to stop at a conflict and say so, because "
                            "going past one leaves a tree nobody described")
        rc, _, _ = win.git(plat, "rev-parse", "-q", "--verify", "REVERT_HEAD", check=False)
        if rc == 0:
            findings.append("a conflicted revert was left in the index: the next step "
                            "would meet a repository it cannot even read")

    # ── (5) an edit the tree no longer matches is refused ────────────
    if picked:
        pin = pins.read(str(plat))[(picked[0].cls, picked[0].name)]

        class Stale:
            cls, name, where = pin.cls, pin.name, pin.where
            current, digest, key = "a-version-this-tree-never-had", None, pin.key
        try:
            win.rewrite(plat, Stale(), version="9.9.9")
            findings.append("an edit was written into a line that does not carry the "
                            "version the inventory recorded: between a stale inventory "
                            "and a blind write, the only safe answer is to stop")
        except win.RefusedEdit:
            pass
finally:
    shutil.rmtree(tmp, ignore_errors=True)

for f in findings:
    print(f)
print(f"SCOPE: {len(picked)} class(es) of pin edited, committed and reverted over a real "
      f"copy of the seed's platform")
