"""Check 286 — what a backup or a restore stages in the clear dies with
the call, overwritten, however the call ends.

REVIEW of 2026-10-13 (A-9): `aegis data` staged the dumps of every
database, the bundle a restore unpacks and the copy a remote restore
downloads with mkdtemp() under /tmp and removed them with rmtree in a
`finally`; a TERM (a stopped timer, a closed terminal) runs no `finally`
in Python, so the plaintext stayed under /tmp, and an rmtree frees the
blocks without overwriting them. `aegis state backup|restore` staged
under /tmp as well, left through a plain rm -rf, and only on EXIT.

Read, comment-stripped: aegis-data stages through staging_dir (born 0700
under the instance, never /tmp: a dump can be larger than the RAM, so
not /dev/shm either), removes through shred_tree, and main arms TERM
and HUP into SystemExit so that every `finally` runs; state/backup and
state/restore stage under /dev/shm, shred before they remove, and trap
INT/TERM as well as EXIT.
Driven: shred_tree over a tree that carries a token — at the moment each
file is unlinked it no longer carries it; a process armed the way main
arms itself, hit by a TERM inside a try/finally — the staging it made is
gone and the exit code says TERM; `aegis state backup` over a sandbox
instance with a real age: the bundle decrypts, and nothing in /dev/shm
carries the token afterwards, also when a TERM hits the call while its
sink holds; `aegis state restore` of that bundle into a fresh home: the
state is placed and nothing in /dev/shm carries the token.
"""
import glob
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = os.path.abspath(sys.argv[1])
# the instance's variables never reach the sandbox: the verifier runs with
# the operator's AEGIS_* exported, and a driver that inherits them writes
# into the live instance (a gates.jsonl under ~/aegis, 2026-10-14)
_clean = {k: v for k, v in os.environ.items()
          if not (k.startswith("AEGIS_") or k in ("PLATFORM_DIR", "SOPS_AGE_KEY_FILE", "AGE_PUBLIC"))}
findings = []
scope = []


def code(rel):
    try:
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    except OSError:
        findings.append(f"{rel} is missing")
        return ""
    return "\n".join(l for l in text.splitlines() if not re.match(r"^\s*#", l))


def py_body(fn, text):
    """A top-level python function, up to the next top-level statement."""
    out, inside = [], False
    for l in text.splitlines():
        if not inside and l.startswith(f"def {fn}("):
            inside = True
            out.append(l)
            continue
        if inside:
            if l and not l[0].isspace():
                break
            out.append(l)
    return "\n".join(out)


def sh_body(fn, text):
    out, inside = [], False
    for l in text.splitlines():
        if not inside and l.startswith(fn + "()"):
            inside = True
        if inside:
            out.append(l)
            if l.startswith("}"):
                break
    return "\n".join(out)


# ── read: aegis-data ─────────────────────────────────────────────────────
data = code("libexec/aegis-data")
cur, lines = None, []
for l in data.splitlines():
    m = re.match(r"def (\w+)\(", l)
    if m:
        cur = m.group(1)
    lines.append((cur, l))
for fn, l in lines:
    if "tempfile.mkdtemp(" in l and fn not in ("store_write", "staging_dir"):
        findings.append(f"aegis-data: {fn} stages with mkdtemp outside staging_dir: under /tmp, on disk, never overwritten")
    if "shutil.rmtree(" in l and fn not in ("store_write", "shred_tree"):
        findings.append(f"aegis-data: {fn} removes its staging with rmtree: the blocks keep the plaintext")
for fn, want in (("capture_org", 2), ("open_bundle", 1), ("main", 1)):
    n = sum(1 for f, l in lines if f == fn and "staging_dir(" in l)
    if n < want:
        findings.append(f"aegis-data: {fn} stages through staging_dir {n} time(s), {want} expected")
root_line = next((l for _, l in lines if l.startswith("STAGING_ROOT =")), "")
if '".staging"' not in root_line or "aegis_home" not in root_line:
    findings.append("aegis-data: the staging root is not .staging under the instance")
if "STAGING_ROOT" not in py_body("staging_dir", data):
    findings.append("aegis-data: staging_dir does not stage under the staging root")
sh = py_body("shred_tree", data)
if '"r+b"' not in sh or "os.unlink(" not in sh:
    findings.append("aegis-data: shred_tree does not overwrite the files before it unlinks them")
arm = py_body("arm_signals", data)
if not ("signal.SIGTERM" in arm and "signal.SIGHUP" in arm and "signal.signal(" in arm):
    findings.append("aegis-data: arm_signals does not turn TERM and HUP into an exit that runs the finally blocks")
if "arm_signals()" not in py_body("main", data):
    findings.append("aegis-data: main does not arm the signals: a TERM leaves the staging in place")
scope.append("aegis-data read (its staging sites, staging_dir, shred_tree, arm_signals, main)")

# ── read: state/backup and state/restore ─────────────────────────────────
for rel, var in (("libexec/state/backup", "STAGE"), ("libexec/state/restore", "TMP")):
    t = code(rel)
    short = rel.split("/", 1)[1]
    m = re.search(r'^' + var + r'="[$][(]mktemp -d ([^)]*)[)]"', t, re.M)
    if not m:
        findings.append(f"{short} no longer stages through `mktemp -d` into {var}: re-aim this check")
    elif "$STAGE_ROOT/" not in m.group(1):
        findings.append(f"{short} stages {var} under the default tmp dir: on disk, and not where the cleanup looks")
    if not re.search(r"^SHM=/dev/shm$", t, re.M):
        findings.append(f"{short} does not name /dev/shm for its staging")
    if "df -B1 --output=avail" not in t or '.staging"' not in t:
        findings.append(f"{short} does not measure whether the payload fits in tmpfs, with the instance's disk as the fallback")
    if "shred -u" not in sh_body("stage_cleanup", t):
        findings.append(f"{short} removes its staging without shredding it")
    if not re.search(r"^trap 'stage_cleanup; exit 130' INT TERM$", t, re.M):
        findings.append(f"{short} does not trap INT/TERM into the cleanup: a Ctrl-C is left to bash's own handling")
    if not re.search(r"^trap 'stage_cleanup' EXIT$", t, re.M):
        findings.append(f"{short} does not trap EXIT into the cleanup: a die leaves the staging")
    if rel.endswith("backup") and not re.search(r'^\s*VER="[$]STAGE/', t, re.M):
        findings.append("state/backup stages the roundtrip's copy outside the staging dir: the cleanup does not take it")
scope.append("state/backup and state/restore read")

# ── drive ────────────────────────────────────────────────────────────────
SHM = "/dev/shm"
DATA = os.path.join(ROOT, "libexec", "aegis-data")

LOAD = (   # the command has no .py suffix: the source loader is named
    "import importlib.machinery, importlib.util, os, sys\n"
    "loader = importlib.machinery.SourceFileLoader('aegis_data', sys.argv[1])\n"
    "spec = importlib.util.spec_from_loader('aegis_data', loader)\n"
    "mod = importlib.util.module_from_spec(spec)\n"
    "loader.exec_module(mod)\n"
)
SPY = LOAD + (
    "token = sys.argv[2].encode()\n"
    "d = mod.staging_dir('probe-')\n"
    "print('ROOT', d, oct(os.stat(d).st_mode & 0o777), oct(os.stat(os.path.dirname(d)).st_mode & 0o777))\n"
    "os.makedirs(os.path.join(d, 'payload'))\n"
    "for name in ('a.sql', 'payload/b.bin'):\n"
    "    open(os.path.join(d, name), 'wb').write(token * 3)\n"
    "seen = []\n"
    "real = os.unlink\n"
    "def spy(p, *a, **k):\n"
    "    try:\n"
    "        seen.append(token in open(p, 'rb').read())\n"
    "    except OSError:\n"
    "        seen.append(None)\n"
    "    return real(p, *a, **k)\n"
    "os.unlink = spy\n"
    "mod.shred_tree(d)\n"
    "print('GONE' if not os.path.exists(d) else 'LEFT')\n"
    "print('UNLINKED', len(seen), 'CARRYING', sum(1 for s in seen if s))\n"
)
TERM = LOAD + (
    "import time\n"
    "mod.arm_signals()\n"
    "d = mod.staging_dir('probe-')\n"
    "open(os.path.join(d, 'x'), 'wb').write(b'x')\n"
    "print('DIR', d, flush=True)\n"
    "try:\n"
    "    time.sleep(30)\n"
    "finally:\n"
    "    mod.shred_tree(d)\n"
    "    print('FINALLY', 'GONE' if not os.path.exists(d) else 'LEFT', flush=True)\n"
)


def carrying(token):
    hits = []
    for base, dirs, files in os.walk(SHM, onerror=lambda e: None):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(base, d))]
        for f in files:
            p = os.path.join(base, f)
            try:
                if os.path.islink(p) or os.path.getsize(p) > 1 << 20:
                    continue
                with open(p, "rb") as fh:
                    if token in fh.read():
                        hits.append(os.path.relpath(p, SHM))
            except OSError:
                continue
    return sorted(hits)


def destroy_shm(paths):
    """What a run left under /dev/shm is ours (the token says so): the whole
    staging entry goes, its files overwritten first."""
    for top in sorted({rel.split("/", 1)[0] for rel in paths}):
        if not top.startswith("aegis-state."):
            continue
        root = os.path.join(SHM, top)
        for base, dirs, files in os.walk(root, topdown=False):
            for f in files:
                q = os.path.join(base, f)
                try:
                    n = os.path.getsize(q)
                    with open(q, "r+b") as fh:
                        fh.write(b"0" * n)
                    os.unlink(q)
                except OSError:
                    pass
            for d in dirs:
                try:
                    os.rmdir(os.path.join(base, d))
                except OSError:
                    pass
        try:
            os.rmdir(root)
        except OSError:
            pass


missing = [t for t in ("age", "age-keygen", "shred") if not shutil.which(t)]
if missing:
    findings.append(f"{', '.join(missing)} not on this machine: the staging cannot be driven here")
elif not os.path.isdir(SHM):
    findings.append("/dev/shm does not exist here: the staging cannot be driven")
else:
    with tempfile.TemporaryDirectory() as tmp:
        home = os.path.join(tmp, "home")
        os.makedirs(home)
        env = dict(_clean, HOME=home, AEGIS_ROOT=ROOT, AEGIS_HOME=home)

        # (a) shred_tree: born 0700 under the instance, overwritten before unlinked
        token = "PROBE-286-" + uuid.uuid4().hex
        p = subprocess.run([sys.executable, "-c", SPY, DATA, token], capture_output=True, text=True,
                           env=env, timeout=120)
        out = p.stdout
        m = re.search(r"^ROOT (\S+) (\S+) (\S+)$", out, re.M)
        if p.returncode != 0 or not m:
            findings.append(f"the staging helpers could not be driven (rc {p.returncode}): {(p.stderr or out)[-200:]!r}")
        else:
            d, mode, pmode = m.groups()
            if not d.startswith(os.path.join(home, ".staging") + os.sep):
                findings.append(f"the staging was born at {d}, not under the instance's .staging")
            if mode != "0o700" or pmode != "0o700":
                findings.append(f"the staging is born {mode} inside a {pmode} dir, not 0700 in 0700")
            if "GONE" not in out.splitlines():
                findings.append("shred_tree left the staging dir in place")
            mu = re.search(r"^UNLINKED (\d+) CARRYING (\d+)$", out, re.M)
            if not mu or mu.group(1) != "2":
                findings.append(f"shred_tree did not unlink the two files it was given: {out[-120:]!r}")
            elif mu.group(2) != "0":
                findings.append(f"{mu.group(2)} of 2 files still carried their content when they were unlinked: "
                                "the blocks keep the plaintext")
        scope.append("shred_tree driven over a tree with a token")

        # (b) a TERM runs the finally: the staging is gone, the exit code says TERM
        p = subprocess.Popen([sys.executable, "-c", TERM, DATA], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, env=env, start_new_session=True)
        line = p.stdout.readline()
        md = re.match(r"^DIR (\S+)$", line)
        if md:
            time.sleep(0.3)
            os.kill(p.pid, signal.SIGTERM)
        try:
            rest = p.communicate(timeout=60)[0]
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            rest = p.communicate()[0]
        if not md:
            findings.append(f"the TERM case could not be driven: {(line + rest)[-200:]!r}")
        else:
            if "FINALLY GONE" not in rest:
                findings.append("a TERM did not run the finally: the staging stays in place "
                                f"(rc {p.returncode}, {rest[-120:]!r})")
            if os.path.isdir(md.group(1)):
                findings.append(f"after a TERM the staging {md.group(1)} is still there")
            if p.returncode != 143:
                findings.append(f"a TERM ended with exit {p.returncode}, not 143: the caller cannot tell a signal from a failure")
        scope.append("a TERM against a process armed as main arms itself")

        # (c) aegis state backup over a sandbox instance, with a real age
        key = os.path.join(tmp, "age.key")
        subprocess.run(["age-keygen", "-o", key], capture_output=True, check=True)
        recipient = re.search(r"public key: (age1\S+)", open(key).read()).group(1)
        token = "PROBE-286-" + uuid.uuid4().hex
        os.makedirs(os.path.join(home, ".state-secrets"), mode=0o700)
        os.makedirs(os.path.join(home, ".init-state"), mode=0o700)
        with open(os.path.join(home, ".state-secrets", "probe.enc"), "w") as f:
            f.write(token + "\n")
        with open(os.path.join(home, ".init-state", "gates.jsonl"), "w") as f:
            f.write('{"gate":"probe"}\n')
        with open(os.path.join(home, ".age-public"), "w") as f:
            f.write(recipient + "\n")
        backups = os.path.join(tmp, "backups")
        benv = dict(env, SOPS_AGE_KEY_FILE=key, AEGIS_BACKUPS=backups)
        benv.pop("AEGIS_BACKUP_SINK", None)
        p = subprocess.run(["bash", os.path.join(ROOT, "libexec", "state", "backup")], capture_output=True,
                           text=True, env=benv, timeout=120)
        bundles = sorted(glob.glob(os.path.join(backups, "platform", "aegis-state-*.age")))
        if p.returncode != 0 or not bundles:
            findings.append(f"aegis state backup over the sandbox exited {p.returncode}: {(p.stderr or p.stdout)[-200:]!r}")
        else:
            lst = subprocess.run(["bash", "-c", 'age -d -i "$1" "$2" | tar -tz', "-", key, bundles[-1]],
                                 capture_output=True, text=True, timeout=60)
            if "state-secrets/probe.enc" not in lst.stdout:
                findings.append("the state bundle does not carry the store: the staging change broke the backup")
            if "ROUNDTRIP OK" not in p.stdout:
                findings.append("the backup's roundtrip was not proven")
        left = carrying(token.encode())
        if left:
            findings.append(f"after a backup the staging is still in /dev/shm: {', '.join(left)}")
            destroy_shm(left)
        # (d) a TERM while the sink holds the call
        hold_glob = os.path.join(backups, "platform", "*.hold")
        for h in glob.glob(hold_glob):
            os.unlink(h)
        senv = dict(benv, AEGIS_BACKUP_SINK=': > "$AEGIS_BACKUP_BUNDLE.hold"; sleep 30')
        p = subprocess.Popen(["bash", os.path.join(ROOT, "libexec", "state", "backup")], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, env=senv, start_new_session=True)
        for _ in range(300):
            if glob.glob(hold_glob):
                break
            time.sleep(0.1)
        else:
            findings.append("the backup never reached its sink: the TERM case could not be driven")
        time.sleep(0.3)
        os.killpg(p.pid, signal.SIGTERM)
        try:
            out = p.communicate(timeout=60)[0]
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            out = p.communicate()[0]
        if p.returncode == 0:
            findings.append("a TERM during the sink ended with exit 0")
        left = carrying(token.encode())
        if left:
            findings.append(f"a TERM during the sink left the staging in /dev/shm: {', '.join(left)}")
            destroy_shm(left)
        # (d') a tmpfs that is too small (a df that reports nothing free): the staging goes
        #      to the instance's disk, is said, and nothing of it stays there
        fakebin = os.path.join(tmp, "fakebin")
        os.makedirs(fakebin, exist_ok=True)
        with open(os.path.join(fakebin, "df"), "w") as f:
            f.write("#!/bin/sh\nprintf 'Avail\\n0\\n'\n")
        os.chmod(os.path.join(fakebin, "df"), 0o755)
        denv = dict(benv, PATH=fakebin + os.pathsep + benv["PATH"])
        p = subprocess.run(["bash", os.path.join(ROOT, "libexec", "state", "backup")], capture_output=True,
                           text=True, env=denv, timeout=120)
        staging = os.path.join(home, ".staging")
        if p.returncode != 0 or "ROUNDTRIP OK" not in p.stdout:
            findings.append(f"with a tmpfs too small the backup failed (rc {p.returncode}): {(p.stderr or p.stdout)[-200:]!r}")
        if "staging on disk under " + staging not in p.stdout:
            findings.append("with a tmpfs too small the staging did not go to the instance's .staging, or it was not said")
        elif os.listdir(staging):
            findings.append(f"the staging on disk outlived the call: {os.listdir(staging)}")
        left = carrying(token.encode())
        if left:
            findings.append(f"with a tmpfs too small the staging still went to /dev/shm: {', '.join(left)}")
            destroy_shm(left)
        scope.append("aegis state backup driven over a sandbox instance with a real age, once to the end, once "
                     "with a TERM while the sink holds, and once with a tmpfs too small for the payload")

        # (e) aegis state restore of that bundle into a fresh home
        if bundles:
            home2 = os.path.join(tmp, "home2")
            os.makedirs(home2)
            renv = dict(env, HOME=home2, AEGIS_HOME=home2, SOPS_AGE_KEY_FILE=key)
            p = subprocess.run(["bash", os.path.join(ROOT, "libexec", "state", "restore"), bundles[-1]],
                               capture_output=True, text=True, env=renv, timeout=120)
            placed = os.path.join(home2, ".state-secrets", "probe.enc")
            if p.returncode != 0 or not os.path.isfile(placed) or open(placed).read().strip() != token:
                findings.append(f"aegis state restore did not place the store (rc {p.returncode}): "
                                f"{(p.stderr or p.stdout)[-200:]!r}")
            left = carrying(token.encode())
            if left:
                findings.append(f"after a restore the staging is still in /dev/shm: {', '.join(left)}")
                destroy_shm(left)
            # and the same restore with a tmpfs too small: on disk, said, and gone
            home3 = os.path.join(tmp, "home3")
            os.makedirs(home3)
            renv3 = dict(renv, HOME=home3, AEGIS_HOME=home3, PATH=fakebin + os.pathsep + renv["PATH"])
            p = subprocess.run(["bash", os.path.join(ROOT, "libexec", "state", "restore"), bundles[-1]],
                               capture_output=True, text=True, env=renv3, timeout=120)
            staging3 = os.path.join(home3, ".staging")
            if p.returncode != 0 or not os.path.isfile(os.path.join(home3, ".state-secrets", "probe.enc")):
                findings.append(f"with a tmpfs too small the restore failed (rc {p.returncode}): {(p.stderr or p.stdout)[-200:]!r}")
            if "staging on disk under " + staging3 not in p.stdout:
                findings.append("with a tmpfs too small the restore's staging did not go to .staging, or it was not said")
            elif os.listdir(staging3):
                findings.append(f"the restore's staging on disk outlived the call: {os.listdir(staging3)}")
            scope.append("aegis state restore of that bundle into a fresh home, with a real tmpfs and with one too small")

print("SCOPE: " + "; ".join(scope))
for f in findings:
    print(f)
