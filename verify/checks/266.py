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
afterwards, with no refusal, and SAY it took commits in; a clone that
diverged must be refused, never merged. In aegis-image the two verbs that
act (request, gc) take in the remote on a real run, and the reads (list,
check) do not.
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
    notes = []
    refusals = window.preflight(platform=str(clone), conf={}, hooks=hooks, notes=notes)
    if len(notes) != 1 or "1 commit(s) behind" not in notes[0]:
        findings.append(f"the clone was fast-forwarded and nobody was told (notes: {notes}): a merge in silence")
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

# A git that cannot answer is a refusal, never a hang or a traceback:
# a remote that asks for credentials, or one that does not answer. Driven
# with a git on PATH that records what it was given and then hangs.
with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    fake = tmp / "git"
    fake.write_text('#!/bin/sh\nprintf "%s" "${GIT_TERMINAL_PROMPT:-unset}" > "$(dirname "$0")/prompt"\nexec sleep 30\n')
    fake.chmod(0o755)
    path_was, timeout_was = os.environ["PATH"], window.GIT_TIMEOUT
    os.environ["PATH"] = f"{tmp}:{path_was}"
    window.GIT_TIMEOUT = 1
    try:
        window.catch_up(str(tmp))
        findings.append("a git that never answered let catch_up return: the window would act on a clone nobody brought up")
    except window.GitTrouble:
        pass
    except Exception as e:                                # noqa: BLE001
        findings.append(f"a git that does not answer ends in {type(e).__name__}, not GitTrouble: "
                        f"the preflight of update and app apply dies in a traceback instead of a refusal")
    finally:
        os.environ["PATH"], window.GIT_TIMEOUT = path_was, timeout_was
    seen = (tmp / "prompt").read_text() if (tmp / "prompt").is_file() else "never ran"
    if seen != "0":
        findings.append(f"git runs with GIT_TERMINAL_PROMPT={seen}: a remote that asks for "
                        f"credentials waits on a prompt nobody sees")

img = (pathlib.Path(ROOT) / "libexec" / "aegis-image").read_text(encoding="utf-8")


def body_of(fn):
    m = re.search(r"^%s\(\) \{\n(.*?)^\}" % re.escape(fn), img, re.S | re.M)
    if not m:
        findings.append(f"aegis-image has no {fn}(): re-aim this check")
        return ""
    return "\n".join(l for l in m.group(1).splitlines() if not l.lstrip().startswith("#"))


sync = body_of("sync_before_writing")
if sync and not (re.search(r"^\s*dry && return 0$", sync, re.M)
                 and re.search(r'^\s*\[\[ "\$LIST_ROOT" == "\$PLATFORM_DIR" \]\] \|\| return 0$', sync, re.M)
                 and re.search(r"^\s*platform_repo_sync$", sync, re.M)):
    findings.append("sync_before_writing does not take in the remote on a real run against the instance (or does it on a dry one)")
# THE TWO THAT ACT take in the remote, right after the list is found...
for fn in ("do_request", "do_gc"):
    b_ = body_of(fn)
    if b_ and not re.search(r"^\s*need_list\n(?:.*\n)*?\s*sync_before_writing$", b_, re.M):
        findings.append(f"aegis image's {fn} does not take in the remote before it acts: it works on a clone the remote moved past")
# ...and the ones that only READ do not: a read that fetches, merges and
# dies without a network is not a read (it sat in need_list for a few
# hours on 2026-10-02).
for fn in ("need_list", "do_list", "do_check"):
    b_ = body_of(fn)
    if re.search(r"\b(platform_repo_sync|sync_before_writing)\b", b_):
        findings.append(f"aegis image's {fn} is a read and takes in the remote: `image list` and `image check` fetch, merge and die offline")

for x in findings:
    print(x)
print("SCOPE: update's preflight runs between a bare remote and two clones (behind; diverged); a git that hangs; aegis-image's five list-reading functions read")
