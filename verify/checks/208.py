"""Check 208 — the window refuses before it touches anything.

THE WITNESS. The hooks in the fixture do one thing: they create a file.
So the question «did the window touch anything» has a yes-or-no answer
on disk, and it is asked after every refusal. A window that collected
its refusals, printed them, and had already deployed the operator's
maintenance page would be reporting honestly about damage it had
already done.

Four situations, and the window has to stop before the first hook in
every one of them:

  1. the platform repo has uncommitted work in it;
  2. it has commits the remote has not got;
  3. one maintenance hook is configured and the other is not;
  4. the photo cannot be taken.

The fourth is the one that is easy to get wrong, because by then the
refusals have all passed and the window feels open. It is not: with no
before there is nothing for a rollback to come back TO, and raising a
page over an instance you cannot describe is how a two-hour window
becomes a two-day one.

And a fifth property, which is about the list and not about any one
item: ALL the refusals come out of ONE run. An operator who fixes one
and runs again only to meet the next is being made to discover the list
one night at a time.
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
    print(f"lib/aegis/window.py cannot be imported ({e}): the refusals were not exercised")
    print("SCOPE: nothing was exercised")
    sys.exit(0)


def git(root, *a, check=True):
    r = subprocess.run(["git", "-C", str(root), *a], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(a)}: {r.stderr.strip()[:200]}")
    return r.stdout.rstrip("\n")


tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-208-"))
scope = []
try:
    home = tmp / "home"
    plat = home / "platform"
    bare = tmp / "remote.git"
    witness = tmp / "the-hook-ran"
    plat.mkdir(parents=True)
    (plat / "README.md").write_text("a platform\n", encoding="utf-8")
    git(plat, "init", "-q", "-b", "main")
    git(plat, "config", "user.email", "check208@aegis.invalid")
    git(plat, "config", "user.name", "check 208")
    git(plat, "add", "-A")
    git(plat, "commit", "-qm", "first")
    subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
    git(plat, "remote", "add", "origin", str(bare))
    git(plat, "push", "-q", "-u", "origin", "main")

    conf = home / "aegis.conf"

    def write_conf(on, off):
        conf.write_text(f'MAINTENANCE_ON="{on}"\nMAINTENANCE_OFF="{off}"\n', encoding="utf-8")

    hook_on = f"touch {witness}"
    hook_off = f"rm -f {witness}"

    # ── a sealed product root ────────────────────────────────────────
    # A VERIFIER MUST NOT BE ABLE TO TOUCH THE LIVE MACHINE, and this
    # fixture drives a command whose whole job is to touch things. Two
    # walls, because one of them is the one that would be forgotten:
    #
    #   · the product root is a copy with `aegis-check` missing, which
    #     is what makes the photo impossible ON PURPOSE, plus every
    #     other command that talks to the cluster left out — so that a
    #     window which (under a mutation) walks PAST the photo still
    #     cannot reach anything;
    #   · a `bin` of its own at the front of PATH with a `kubectl` and a
    #     `systemctl` that refuse. The window reads services and stops
    #     the backup timer through those two, and a mutation that lets
    #     it get that far would otherwise stop the operator's real
    #     backup clock from inside a check that is supposed to only
    #     read. Thirty-two of those run in parallel.
    prod = tmp / "product"
    prod.mkdir()
    (prod / "libexec").mkdir()
    SEALED = {"aegis-check", "aegis-ci", "aegis-sync", "aegis-image", "aegis-init",
              "aegis-state", "aegis-data", "aegis-org", "aegis-destroy", "aegis-rotate"}
    for name in os.listdir(os.path.join(ROOT, "libexec")):
        if name in SEALED:
            continue
        os.symlink(os.path.join(ROOT, "libexec", name), prod / "libexec" / name)
    for d in ("lib", "share", "seed", "verify", "init", "bin"):
        if os.path.isdir(os.path.join(ROOT, d)):
            os.symlink(os.path.join(ROOT, d), prod / d)
    fakebin = tmp / "bin"
    fakebin.mkdir()
    for name in ("kubectl", "systemctl", "helm", "sudo", "apt-get"):
        f = fakebin / name
        f.write_text("#!/bin/sh\necho 'sealed by check 208' >&2\nexit 1\n",
                     encoding="utf-8")
        f.chmod(0o755)

    def run_window():
        witness.unlink(missing_ok=True)
        env = {**os.environ, "AEGIS_ROOT": str(prod), "AEGIS_HOME": str(home),
               "AEGIS_CONF": str(conf), "PLATFORM_DIR": str(plat),
               "AEGIS_CMD": "aegis",
               "PATH": f"{fakebin}:{os.environ.get('PATH', '')}"}
        r = subprocess.run([sys.executable, str(prod / "libexec" / "aegis-update"),
                            "window", "--yes", "--json"],
                           capture_output=True, text=True, env=env, timeout=600)
        try:
            doc = json.loads(r.stdout)
        except ValueError:
            doc = {"steps": [], "rc": r.returncode, "raw": r.stdout[:400],
                   "err": r.stderr[-400:]}
        return doc, witness.exists()

    def names(doc):
        return [s.get("step", "") for s in doc.get("steps", [])]

    # ── 1 + 2 + 3 at once: they must ALL come out of one run ─────────
    write_conf(hook_on, "")                       # half configured
    (plat / "somebody-elses-work.txt").write_text("not the window's\n", encoding="utf-8")
    (plat / "README.md").write_text("a platform, edited\n", encoding="utf-8")
    git(plat, "commit", "-qam", "a commit the remote has not got")
    doc, ran = run_window()
    got = names(doc)
    scope.append("dirty + unpushed + half-configured hooks")
    for want in ("refuse:platform-dirty", "refuse:platform-unpushed",
                 "refuse:maintenance-half-configured"):
        if want not in got:
            findings.append(f"a repo that is dirty, unpushed AND half-configured did not "
                            f"produce «{want}» — it produced {got}")
    if len(got) != len([g for g in got if g.startswith("refuse:")]):
        findings.append(f"the window did something besides refusing: {got}")
    if ran:
        findings.append("THE MAINTENANCE HOOK RAN even though the window refused: the "
                        "refusals are collected before anything is touched, or they are "
                        "decoration")
    if doc.get("rc") != 1:
        findings.append(f"a refused window exited {doc.get('rc')} and not 1")

    # ── the tree is put in order, one thing at a time ────────────────
    (plat / "somebody-elses-work.txt").unlink()
    git(plat, "push", "-q", "origin", "main")
    doc, ran = run_window()
    got = names(doc)
    scope.append("only the hooks are half configured")
    if "refuse:maintenance-half-configured" not in got:
        findings.append(f"a way in with no way out was not refused: {got}")
    if ran:
        findings.append("the hook ran on a window refused for its half-configured hooks")

    # ── 4: everything in order, and no photo can be taken ────────────
    write_conf(hook_on, hook_off)
    doc, ran = run_window()
    got = names(doc)
    scope.append("nothing refuses, and the photo cannot be taken")
    if [g for g in got if g.startswith("refuse:")]:
        findings.append(f"a clean, pushed repo with both hooks was still refused: {got}")
    if "window:photo" not in got:
        findings.append(f"the window did not even reach the photo: {got}")
    else:
        st = [s for s in doc["steps"] if s["step"] == "window:photo"][0]
        if st.get("state") != "not-evaluable":
            findings.append(f"the photo could not be taken and the window called it "
                            f"«{st.get('state')}»: a photo that failed is «could not "
                            f"evaluate», never a failure of the instance and never a pass")
    if ran:
        findings.append("THE MAINTENANCE HOOK RAN with no photo taken: with no before "
                        "there is nothing for a rollback to come back to, and the page "
                        "went up over an instance nobody had described")
    if doc.get("rc") != 2:
        findings.append(f"a window that could not photograph exited {doc.get('rc')} and "
                        f"not 2")
    # And it left no window directory behind: `status` reports on windows
    # that happened, and a refusal did not happen.
    d = home / ".init-state" / "updates"
    if d.is_dir() and any(p.is_dir() for p in d.iterdir()):
        findings.append("a window that never opened left a directory behind: "
                        "`update status` would report on something that did not happen")

    # ── the dry run touches nothing either ───────────────────────────
    witness.unlink(missing_ok=True)
    env = {**os.environ, "AEGIS_ROOT": str(prod), "AEGIS_HOME": str(home),
           "AEGIS_CONF": str(conf), "PLATFORM_DIR": str(plat),
           "PATH": f"{fakebin}:{os.environ.get('PATH', '')}"}
    r = subprocess.run([sys.executable, str(prod / "libexec" / "aegis-update"),
                        "window", "--json"], capture_output=True, text=True,
                       env=env, timeout=600)
    scope.append("dry")
    if witness.exists():
        findings.append("the DRY window ran the maintenance hook: without --yes not one "
                        "hook runs, which is the same rule `aegis destroy` follows")
    if r.returncode not in (0, 1, 2):
        findings.append(f"a dry window over a tree with nothing wrong exited "
                        f"{r.returncode}")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

for f in findings:
    print(f)
print(f"SCOPE: {len(scope)} situation(s) driven end to end ({'; '.join(scope)}), with a "
      f"hook that writes a file so «did it touch anything» has an answer on disk")
