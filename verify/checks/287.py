"""Check 287 — the dossier of a run is born readable by its owner only,
whatever the operator's umask.

REVIEW of 2026-10-13 (A-9): `aegis init-log` runs the init under
script(1) and keeps the WHOLE run — stdout and stderr, whatever any tool
printed — in <instance>/.init-state/runs/. script(1) created that file
under the operator's umask: with the default 022 it was 0644 in a 0755
dir, readable by every account on the host.

Read, comment-stripped: the runs dir is made 0700, and the dossier is
created 0600 (umask 077 in a subshell) BEFORE script(1) opens it.
Driven, over a sandbox product whose init is a stand-in that writes to
both streams and exits 7, under umask 022: the dossier is 0600 in a
0700 dir, carries both streams, the exit code is the init's, and the
path is printed before the run; a runs dir that already exists 0755 (an
instance from before) is tightened to 0700. The init's own umask is not
the wrapper's business: the stand-in reports the umask it runs with,
which must be the operator's.
"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
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


# ── read ─────────────────────────────────────────────────────────────────
il = code("libexec/aegis-init-log")
lines = il.splitlines()
i_chmod = next((i for i, l in enumerate(lines) if re.search(r'chmod 700 "\$RUNS"', l)), None)
i_born = next((i for i, l in enumerate(lines) if re.search(r'umask 077; : > "\$LOG"', l)), None)
i_script = next((i for i, l in enumerate(lines) if "script -qefc" in l), None)
if i_chmod is None:
    findings.append("aegis-init-log does not make the runs dir 0700")
if i_born is None:
    findings.append("aegis-init-log does not create the dossier 0600 itself: script(1) creates it under the operator's umask")
elif i_script is not None and i_born > i_script:
    findings.append("the dossier is made 0600 only after script(1) wrote it: the run was readable while it ran")
if re.search(r"^\s*umask 077\s*$", il, re.M):
    findings.append("aegis-init-log sets umask 077 for the whole wrapper: the init would run with a umask it does not have without the wrapper")
scope.append("aegis-init-log read")

# ── drive ────────────────────────────────────────────────────────────────
if not shutil.which("script"):
    findings.append("script(1) is not on this machine: the wrapper cannot be driven here")
else:
    with tempfile.TemporaryDirectory() as tmp:
        sandbox = os.path.join(tmp, "product")
        for rel in ("libexec/aegis-init-log", "lib/paths.sh", "share/exit-codes.txt"):
            os.makedirs(os.path.join(sandbox, os.path.dirname(rel)), exist_ok=True)
            shutil.copy(os.path.join(ROOT, rel), os.path.join(sandbox, rel))
        fake = os.path.join(sandbox, "libexec", "aegis-init")
        with open(fake, "w") as f:
            f.write("#!/usr/bin/env bash\n"
                    "echo 'MARKER-OUT-287 args:' \"$@\"\n"
                    "echo 'MARKER-ERR-287' >&2\n"
                    "echo \"umask-of-the-init: $(umask)\"\n"
                    "exit 7\n")
        os.chmod(fake, 0o755)
        os.chmod(os.path.join(sandbox, "libexec", "aegis-init-log"), 0o755)

        def run(home):
            env = dict(_clean, HOME=home, AEGIS_ROOT=sandbox, AEGIS_HOME=home)
            return subprocess.run(["bash", "-c", 'umask 022; exec "$0" "$@"',
                                   os.path.join(sandbox, "libexec", "aegis-init-log"), "--profile", "cloudflare"],
                                  capture_output=True, text=True, env=env, timeout=120, stdin=subprocess.DEVNULL)

        def mode(p):
            return stat.S_IMODE(os.stat(p).st_mode)

        # (a) a fresh instance, the operator's umask 022
        home = os.path.join(tmp, "home")
        os.makedirs(home)
        p = run(home)
        runs = os.path.join(home, ".init-state", "runs")
        logs = sorted(os.listdir(runs)) if os.path.isdir(runs) else []
        if p.returncode != 7:
            findings.append(f"the wrapper exited {p.returncode}, not the init's 7: {(p.stderr or p.stdout)[-160:]!r}")
        if not logs:
            findings.append(f"no dossier was written under {runs}: {(p.stderr or p.stdout)[-160:]!r}")
        else:
            log = os.path.join(runs, logs[-1])
            if not logs[-1].endswith("-cloudflare.log"):
                findings.append(f"the dossier is not named after the profile: {logs[-1]}")
            if mode(log) != 0o600:
                findings.append(f"the dossier is born {oct(mode(log))} under umask 022, not 0600: every account on the host can read the run")
            if mode(runs) != 0o700:
                findings.append(f"the runs dir is {oct(mode(runs))}, not 0700")
            body = open(log, errors="replace").read()
            if "MARKER-OUT-287" not in body or "MARKER-ERR-287" not in body:
                findings.append("the dossier does not carry both streams of the run")
            if "umask-of-the-init: 0022" not in body:
                findings.append("the init ran with a umask that is not the operator's: the wrapper changed it for the whole run")
            first = (p.stdout.splitlines() or [""])[0]
            if not first.startswith("dossier: "):
                findings.append(f"the dossier's path is not the first line printed: {first!r}")
        scope.append("a fresh instance under umask 022")

        # (b) an instance from before, whose runs dir is 0755
        home2 = os.path.join(tmp, "home2")
        runs2 = os.path.join(home2, ".init-state", "runs")
        os.makedirs(runs2)
        os.chmod(runs2, 0o755)
        p = run(home2)
        if mode(runs2) != 0o700:
            findings.append(f"a runs dir that already existed stays {oct(mode(runs2))}: the dossiers of an instance from before remain listable")
        logs2 = sorted(os.listdir(runs2))
        if logs2 and mode(os.path.join(runs2, logs2[-1])) != 0o600:
            findings.append("the dossier of an instance from before is not born 0600")
        scope.append("a runs dir that already existed 0755")

print("SCOPE: " + "; ".join(scope))
for f in findings:
    print(f)
