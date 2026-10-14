"""Check 289 — a host with no kubectl is declared, never a traceback.

REVIEW of 2026-10-13 (M-7): on a machine without kubectl (a clean
container, the product repo on a laptop, the CI runner), `aegis
capacity show` and the producer of `aegis update metrics` died with a
FileNotFoundError from subprocess, in the middle of their document.
Three checks (131, 215, 220) were red there for a reason that had
nothing to do with the artifact, and a console asking the command had
nothing to draw and no reason why.

The product's answer for a cluster nobody could ask is the third
outcome, and a missing binary is the same question: aegis-capacity's
_kubectl turns the OSError into the RuntimeError its caller already
files as not-evaluable; window._kubectl answers rc 127 with the reason,
which every caller already reads as «nobody could ask».

Driven: both commands, over a sandbox instance, with a PATH that holds
everything this one holds except kubectl. The instance's variables
never reach the sandbox (the 286 pattern).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
_clean = {k: v for k, v in os.environ.items()
          if not (k.startswith("AEGIS_") or k in ("PLATFORM_DIR", "SOPS_AGE_KEY_FILE", "AGE_PUBLIC"))}
findings = []
scope = []


def path_without(tool, into):
    """A dir of links to every executable on PATH except <tool>."""
    for d in os.environ.get("PATH", "").split(os.pathsep):
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for n in names:
            if n == tool:
                continue
            dst = os.path.join(into, n)
            if os.path.lexists(dst):
                continue
            try:
                os.symlink(os.path.join(d, n), dst)
            except OSError:
                pass
    return into


with tempfile.TemporaryDirectory(prefix="aegis-289.") as tmp:
    home = os.path.join(tmp, "home")
    os.makedirs(os.path.join(home, "platform"))
    shutil.copy(os.path.join(ROOT, "seed", "platform", "plans.yaml"), os.path.join(home, "platform", "plans.yaml"))
    binp = os.path.join(tmp, "bin")
    os.makedirs(binp)
    path_without("kubectl", binp)
    env = dict(_clean, PATH=binp, HOME=home, AEGIS_HOME=home, AEGIS_ROOT=ROOT, AEGIS_CMD="aegis",
               KUBECONFIG="/dev/null")

    # (a) capacity: a document, rc 2, the reason on the step
    p = subprocess.run([os.path.join(ROOT, "bin", "aegis"), "capacity", "show", "--json"],
                       capture_output=True, text=True, env=env, timeout=120)
    if "Traceback" in (p.stderr or ""):
        findings.append("without kubectl `aegis capacity show --json` dies in a traceback: "
                        f"{(p.stderr or '').strip().splitlines()[-1][:120]}")
    try:
        doc = json.loads(p.stdout)
    except ValueError:
        doc = None
        if "Traceback" not in (p.stderr or ""):
            findings.append(f"without kubectl `aegis capacity show --json` returned no document (rc {p.returncode})")
    if doc is not None:
        steps = doc.get("steps") or []
        ne = [s for s in steps if s.get("state") == "not-evaluable"]
        if doc.get("rc") != 2 or not ne:
            findings.append(f"without kubectl the capacity command answers rc {doc.get('rc')} with states "
                            f"{sorted({s.get('state') for s in steps})}: not the third outcome")
        elif not any("kubectl is not installed" in json.dumps(s) for s in ne):
            findings.append("without kubectl the capacity command is not-evaluable but does not say the "
                            "binary is missing: the operator would look for a dead apiserver")
    scope.append("aegis capacity show --json driven with no kubectl on PATH")

    # (b) the producer of `aegis update metrics`: a document, no traceback
    env_m = dict(env, PLATFORM_DIR=os.path.join(ROOT, "seed", "platform"))
    p = subprocess.run([sys.executable, os.path.join(ROOT, "libexec", "aegis-update"), "metrics", "--json", "--offline"],
                       capture_output=True, text=True, env=env_m, timeout=300)
    if "Traceback" in (p.stderr or ""):
        findings.append("without kubectl `aegis update metrics --json --offline` dies in a traceback: "
                        f"{(p.stderr or '').strip().splitlines()[-1][:120]}")
    else:
        try:
            doc = json.loads(p.stdout)
        except ValueError:
            doc = None
            findings.append(f"without kubectl `aegis update metrics --json` returned no document (rc {p.returncode})")
        if doc is not None and not any(s.get("step", "").startswith("metrics") for s in doc.get("steps") or []):
            findings.append("without kubectl the metrics producer returned a document with no metrics step")
    scope.append("aegis update metrics --json --offline driven with no kubectl on PATH, over the seed's pins")

print("SCOPE: " + "; ".join(scope))
for f in findings:
    print(f)
