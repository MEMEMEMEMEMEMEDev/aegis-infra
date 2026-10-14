"""Check 285 — the copy of the age key the operator reads from another
terminal dies with the phase, however the phase ends.

REVIEW of 2026-10-13 (A-9), read in lib/secrets.sh's ceremony_backup: the
interactive path copied the key to /dev/shm/aegis-resguardo-$$ — outside
the per-phase tmpfs dir that secrets_workdir's traps shred — and removed
it only after the validation gate passed. A wrong paste (the gate dies),
a die anywhere in the validator, or a Ctrl-C at the human pause left the
root of trust in the clear in /dev/shm until the next reboot, next to a
pane that had just told the operator where it was.

Read, comment-stripped: the copy's path is under $SECRETS_TMP;
secrets_workdir traps EXIT and INT/TERM into secrets_cleanup; the cleanup
shreds the files before it removes the dir.
Driven, with the real ceremony (gate_red and human_step answered through
stdin) over a probe file whose content is a token unique to each run: a
validator that fails, an abort at the pause (stdin closed), a TERM while
the pause waits (measured on bash 5.2: the EXIT trap also runs when the
shell dies of a signal at a read, so this case holds through either
trap; the INT/TERM trap is read, as W-03 asked for it), and a validator
that passes. After each run no file in
/dev/shm carries the token and the run's tmpfs dir is gone. The token is
what makes the scan safe next to other runs (the teeth drive this check
in parallel); whatever a run leaves behind is removed once reported, so
a mutation that leaks the copy does not leave probes in /dev/shm.
"""
import os
import re
import select
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


def body_of(fn, text):
    out, inside = [], False
    for l in text.splitlines():
        if not inside and l.startswith(fn + "()"):
            inside = True
        if inside:
            out.append(l)
            if l.startswith("}"):
                break
    return "\n".join(out)


# ── read ─────────────────────────────────────────────────────────────────
sec = code("lib/secrets.sh")
cb = body_of("ceremony_backup", sec)
m = re.search(r'shm_out="([^"]*)"', cb)
if not m:
    findings.append("ceremony_backup no longer names the copy the operator reads (shm_out): re-aim this check")
elif not m.group(1).startswith("$SECRETS_TMP/"):
    findings.append(f"the copy the operator reads lives at {m.group(1)}, outside the phase's tmpfs dir: "
                    "nothing shreds it if the phase dies before the validation")
if 'shm_out="$SECRETS_TMP/' in cb and "SECRETS_TMP:?" not in cb:
    findings.append("ceremony_backup relies on SECRETS_TMP without stating the precondition")
wd = body_of("secrets_workdir", sec)
if not re.search(r"trap 'secrets_cleanup[^']*' INT TERM", wd):
    findings.append("secrets_workdir does not trap INT/TERM into secrets_cleanup: on a Ctrl-C the shred is left to "
                    "bash's own handling of the signal, which W-03 stopped relying on")
if not re.search(r"trap 'secrets_cleanup' EXIT", wd):
    findings.append("secrets_workdir does not trap EXIT into secrets_cleanup: a die leaves the tmpfs dir")
cl = body_of("secrets_cleanup", sec)
if "shred" not in cl:
    findings.append("secrets_cleanup removes the tmpfs dir without shredding its files")
scope.append("ceremony_backup, secrets_workdir and secrets_cleanup read")

# ── drive ────────────────────────────────────────────────────────────────
SHM = "/dev/shm"
PAUSE = b"HUMAN ACTION"      # human_step's banner: printed right before it waits


def carrying(token):
    """Files under /dev/shm whose content carries the token (small files only;
    what cannot be read belongs to someone else and is skipped)."""
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


def destroy(paths, tmpdir):
    """What this run left behind is ours: overwrite, unlink, remove the dir."""
    for rel in paths:
        p = os.path.join(SHM, rel)
        try:
            n = os.path.getsize(p)
            with open(p, "r+b") as fh:
                fh.write(b"\0" * n)
            os.unlink(p)
        except OSError:
            pass
    if tmpdir and os.path.isdir(tmpdir):
        for base, dirs, files in os.walk(tmpdir, topdown=False):
            for f in files:
                try:
                    os.unlink(os.path.join(base, f))
                except OSError:
                    pass
            for d in dirs:
                try:
                    os.rmdir(os.path.join(base, d))
                except OSError:
                    pass
        try:
            os.rmdir(tmpdir)
        except OSError:
            pass


def drain(p, until=None, timeout=60):
    """Read the merged output until EOF, or until a marker shows up."""
    fd = p.stdout.fileno()
    buf = b""
    end = time.monotonic() + timeout
    while True:
        left = end - time.monotonic()
        if left <= 0:
            return buf, False
        r, _, _ = select.select([fd], [], [], left)
        if not r:
            continue
        chunk = os.read(fd, 65536)
        if not chunk:
            return buf, False
        buf += chunk
        if until and until in buf:
            return buf, True


if not os.path.isdir(SHM):
    findings.append("/dev/shm does not exist here: the ceremony cannot be driven")
else:
    with tempfile.TemporaryDirectory() as tmp:
        home = os.path.join(tmp, "home")
        os.makedirs(home)
        env = dict(_clean, HOME=home, AEGIS_ROOT=ROOT, AEGIS_HOME=home, CHECK_MODE="false",
                   AEGIS_NONINTERACTIVE="false", AEGIS_PHASE="probe-285")
        # the tmpfs dir of the run is reported first; the probe key is the token;
        # `good` is a validator that passes only if the copy was there to read:
        pre = ('set -euo pipefail; source "$AEGIS_ROOT/lib/common.sh"; '
               'source "$AEGIS_ROOT/lib/secrets.sh"; secrets_workdir; '
               'printf "TMP285=%s\\n" "$SECRETS_TMP"; '
               'printf "%s" "$PROBE285" > "$SECRETS_TMP/age.key"; '
               'bad() { return 1; }; good() { [[ -s "$SECRETS_TMP/resguardo" ]]; }; ')

        def run(script, stdin, term_at_pause=False):
            token = "PROBE-KEY-285-" + uuid.uuid4().hex
            p = subprocess.Popen(["bash", "-c", pre + script], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=dict(env, PROBE285=token), start_new_session=True)
            p.stdin.write(stdin.encode())
            p.stdin.flush()
            if term_at_pause:
                out, seen = drain(p, until=PAUSE, timeout=30)
                if seen:
                    time.sleep(0.5)          # the lines after the banner, then the read
                    os.killpg(p.pid, signal.SIGTERM)
                rest, _ = drain(p, timeout=30)
                out += rest
            else:
                p.stdin.close()
                out, _ = drain(p, timeout=60)
            try:
                rc = p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                rc = p.wait()
            if term_at_pause:
                p.stdin.close()
            text = out.decode(errors="replace")
            tmpdir = None
            mt = re.search(r"^TMP285=(\S+)$", text, re.M)
            if mt:
                tmpdir = mt.group(1)
            time.sleep(0.2)
            left = carrying(token.encode())
            if tmpdir and os.path.isdir(tmpdir):
                left.append(os.path.relpath(tmpdir, SHM) + "/")
            destroy([l for l in left if not l.endswith("/")], tmpdir)
            return rc, text, token, sorted(left)

        # (a) the validation fails: the gate dies, and nothing stays in /dev/shm
        rc, out, token, left = run('ceremony_backup "age key" "$SECRETS_TMP/age.key" bad', "YES\n\n")
        if rc == 0:
            findings.append("the ceremony ended green with a validator that failed")
        if left:
            findings.append(f"a failed validation left {', '.join(left)} in /dev/shm: the key in the clear")
        # (b) an abort at the human pause (stdin closed): nothing stays
        rc, out, token, left = run('ceremony_backup "age key" "$SECRETS_TMP/age.key" bad', "YES\n")
        if rc == 0:
            findings.append("the ceremony ended green with the pause aborted")
        if left:
            findings.append(f"an abort at the pause left {', '.join(left)} in /dev/shm")
        # (c) a TERM while the pause waits: nothing stays
        rc, out, token, left = run('ceremony_backup "age key" "$SECRETS_TMP/age.key" bad', "YES\n",
                                   term_at_pause=True)
        if PAUSE.decode() not in out:
            findings.append("the ceremony never reached the human pause, so the TERM case could not be driven: "
                            f"{out[-200:]!r}")
        if left:
            findings.append(f"a TERM at the pause left {', '.join(left)} in /dev/shm")
        # (d) the validation passes: the copy was there to read, and nothing stays
        rc, out, token, left = run('ceremony_backup "age key" "$SECRETS_TMP/age.key" good', "YES\n\n")
        if rc != 0:
            findings.append(f"the ceremony failed with a validator that passed (rc {rc}): {out[-160:]!r}")
        if left:
            findings.append(f"a successful ceremony left {', '.join(left)} in /dev/shm")
        if token in out:
            findings.append("the ceremony printed the key to the pane")
        scope.append("the ceremony driven four ways (validator fails, abort at the pause, TERM at the "
                     "pause, validator passes): no copy of the probe in /dev/shm and no tmpfs dir afterwards")

print("SCOPE: " + "; ".join(scope))
for f in findings:
    print(f)
