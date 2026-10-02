"""Check 266 — a command that edits the platform repo first takes in what the remote has.

From plan/21 stage 6 on, image-watch commits the vulnerability ledger and
the exploited-in-the-wild list to the platform repo every morning (and
base-images already committed the provisioner's base there). The two
commands that edit and push that repo from the operator's machine did it
on whatever the clone held: `aegis update` commits a layer and only then
pushes, so a remote that moved overnight refuses the push with the layer
half written; `aegis image request` commits the list and dies at the push
(`aegis image gc` decides a prune on pins that moved).

The sidecar builds a remote and a clone, moves the remote, and RUNS
window.preflight on the clone: the clone must be at the remote's head
afterwards, with no refusal; a clone that diverged must be refused, never
merged. aegis-image's list loader is read for the call, outside a dry run.
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []


def g(cwd, *a):
    return subprocess.run(["git", "-C", str(cwd), *a], capture_output=True, text=True, check=True).stdout.strip()


env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
os.environ.update(env)

from aegis import window  # noqa: E402

with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    remote, clone, other = tmp / "remote.git", tmp / "platform", tmp / "watch"
    subprocess.run(["git", "init", "--quiet", "--bare", "-b", "main", str(remote)], check=True)
    subprocess.run(["git", "clone", "--quiet", str(remote), str(clone)], check=True, capture_output=True)
    (clone / "services.yaml").write_text("a: 1\n")
    g(clone, "add", "services.yaml"); g(clone, "commit", "--quiet", "-m", "seed"); g(clone, "push", "--quiet", "-u", "origin", "main")
    # The watch's morning commit, from another clone.
    subprocess.run(["git", "clone", "--quiet", str(remote), str(other)], check=True, capture_output=True)
    (other / "ledger.txt").write_text("debt|x\n")
    g(other, "add", "ledger.txt"); g(other, "commit", "--quiet", "-m", "chore(watch): ledger"); g(other, "push", "--quiet")
    want = g(other, "rev-parse", "HEAD")

    hooks = window.Hooks({})
    refusals = window.preflight(platform=str(clone), conf={}, hooks=hooks)
    if False:
        pass
    else:
        if refusals:
            findings.append("a clean clone one commit behind was refused: " + "; ".join(r.name for r in refusals))
        if g(clone, "rev-parse", "HEAD") != want:
            findings.append("update's refusals passed and the clone is still behind the remote: the first layer would be committed on yesterday's repo and die at the push")
        # A clone with work of its own AND a remote that moved: refused, not merged.
        (clone / "services.yaml").write_text("a: 2\n")
        g(clone, "commit", "--quiet", "-am", "local"); g(clone, "push", "--quiet")
        g(other, "pull", "--quiet", "--rebase")
        (other / "ledger.txt").write_text("debt|y\n")
        g(other, "commit", "--quiet", "-am", "watch 2"); g(other, "push", "--quiet")
        (clone / "services.yaml").write_text("a: 3\n")
        g(clone, "commit", "--quiet", "-am", "local, unpushed")
        before = g(clone, "rev-parse", "HEAD")
        refusals = window.preflight(platform=str(clone), conf={}, hooks=hooks)
        if not refusals:
            findings.append("a clone that diverged from its remote opened a window")
        if g(clone, "rev-parse", "HEAD") != before:
            findings.append("a clone that diverged was merged by the refusals instead of refused")

img = (pathlib.Path(ROOT) / "libexec" / "aegis-image").read_text(encoding="utf-8")
m = re.search(r"^need_list\(\) \{\n(.*?)^\}", img, re.S | re.M)
if not m:
    findings.append("aegis-image has no need_list(): re-aim this check")
else:
    body = "\n".join(l for l in m.group(1).splitlines() if not l.lstrip().startswith("#"))
    if not re.search(r'if ! dry && \[\[ "\$LIST_ROOT" == "\$PLATFORM_DIR" \]\]; then\s*\n\s*platform_repo_sync\b', body):
        findings.append("aegis-image loads the list without platform_repo_sync on a real run: request and gc work on a clone the remote moved past")

for x in findings:
    print(x)
print("SCOPE: update's preflight runs between a bare remote and two clones (behind; diverged); aegis-image's need_list read")
