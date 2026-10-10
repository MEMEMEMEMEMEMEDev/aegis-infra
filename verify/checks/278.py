"""Check 278 — the ArgoCD admin password comes from the store (#86).

Until 2026-10-10 a new instance was born with the password argocd-server
writes into argocd-initial-admin-secret: outside the store, so `aegis
rotate check` could not measure it and a state backup did not carry it
(#77 found one unrotated for eighteen days; the home instance still had
the installer's on 2026-10-09).

Read, comment-stripped:
  · phase 30 takes it with gen_or_restore, hashes it through htpasswd's
    stdin (never -b, never argv), patches argocd-secret from a file,
    only when the annotation says the Secret holds another password (a
    new passwordMtime closes every session), deletes the installer's
    Secret, and gates both;
  · phase 35 gates a login through the edge in BOTH edge branches, with
    a bounded retry and never a poll (each try spends a failed login on
    «admin», and ArgoCD locks it after five);
  · the rotation table rotates it through phase 30.
Driven: argocd_admin_login_ok against a fake ArgoCD (a curl that answers
by the password in the body) with a real sops + age store — it passes
with the right password, fails when the store's one is rejected, and
fails when ArgoCD accepts ANY password.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
findings = []
scope = []


def code(rel):
    try:
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    except OSError:
        findings.append(f"{rel} is missing")
        return ""
    return "\n".join(l for l in text.splitlines() if not re.match(r"^\s*#", l))


# ── phase 30 ────────────────────────────────────────────────────────────
p30 = code("init/phases/30-argocd.sh")
if not re.search(r'gen_or_restore\s+argocd_admin_pass\b', p30):
    findings.append("phase 30 does not take the ArgoCD admin password from the store: the instance is born "
                    "with the installer's, outside the store and unrotated")
if not re.search(r'htpasswd\s+-n\w*B\w*i\w*[^\n]*<\s*"\$ARGO_ADMIN"', p30) \
        and not re.search(r'htpasswd\s+-n\w*i\w*B\w*[^\n]*<\s*"\$ARGO_ADMIN"', p30):
    findings.append("phase 30 does not hash the admin password through htpasswd's stdin (-i): "
                    "the password would travel in argv")
if re.search(r'htpasswd\s+-\w*b', p30):
    findings.append("phase 30 calls htpasswd with -b: the password in argv")
m = re.search(r'kubectl -n argocd patch secret argocd-secret[^\n]*', p30.replace("\\\n", " "))
if not m or "--patch-file" not in m.group(0):
    findings.append("phase 30 does not patch argocd-secret from a file: the hash and the mark would travel in argv")
if not re.search(r'if \[\[ "\$ARGO_LIVE_MARK" != "\$ARGO_MARK" \]\]; then', p30):
    findings.append("phase 30 re-patches argocd-secret on every run: a new passwordMtime closes every "
                    "open session each time the phase runs")
if not re.search(r'delete secret argocd-initial-admin-secret', p30):
    findings.append("phase 30 leaves argocd-initial-admin-secret: a second, stale copy of the credential")
if not re.search(r'gate "admin-del-almacen"', p30):
    findings.append("phase 30 sets the admin password without a gate on it")
scope.append("phase 30 read")

# ── phase 35 ────────────────────────────────────────────────────────────
p35 = code("init/phases/35-gitops.sh")
gates = re.findall(r'gate "argocd-admin-entra"([^\n]*)', p35)
if len(gates) < 2:
    findings.append(f"phase 35 measures the admin login in {len(gates)} edge branch(es), not in both "
                    "(cloudflare and local)")
for g in gates:
    if "argocd_admin_login_ok" not in g:
        findings.append("phase 35's argocd-admin-entra gate does not run argocd_admin_login_ok")
    if re.search(r'\bpoll\b', g):
        findings.append("phase 35 polls the admin login: every try is a failed login on «admin», and "
                        "ArgoCD locks the account after five")
    t = re.search(r'retry_net\s+(\d+)', g)
    if t and int(t.group(1)) > 4:
        findings.append(f"phase 35 retries the admin login {t.group(1)} times: past five failed logins "
                        "ArgoCD locks «admin»")
scope.append("phase 35 read")

# ── rotation ────────────────────────────────────────────────────────────
rot = open(os.path.join(ROOT, "libexec", "aegis-rotate"), encoding="utf-8").read()
if not re.search(r'^argocd_admin_pass\|normal\|30-argocd\|', rot, re.M):
    findings.append("the rotation table does not rotate argocd_admin_pass through phase 30")

# ── driven: the login helper, against a fake ArgoCD ─────────────────────
FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
body = None
for i, x in enumerate(a):
    if x == "-d" and a[i + 1].startswith("@"):
        body = json.load(open(a[i + 1][1:]))
    if x.startswith("-d@"):
        body = json.load(open(x[3:]))
with open(os.environ["FAKE_LOG"], "a") as f:
    f.write(" ".join(a) + "\n")
mode = os.environ.get("FAKE_MODE", "honest")
good = open(os.environ["FAKE_GOOD"]).read()
ok = body and body.get("username") == "admin" and (mode == "anything" or body.get("password") == good)
if mode == "rejects":
    ok = False
sys.stdout.write("200" if ok else "401")
'''
for tool in ("sops", "age-keygen"):
    if not shutil.which(tool):
        findings.append(f"`{tool}` is not on this machine: the login helper cannot be driven here")
if shutil.which("sops") and shutil.which("age-keygen"):
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "bin")
        store = os.path.join(tmp, "store")
        os.makedirs(bindir)
        os.makedirs(store)
        with open(os.path.join(bindir, "curl"), "w") as f:
            f.write(FAKE_CURL)
        os.chmod(os.path.join(bindir, "curl"), 0o755)
        key = os.path.join(tmp, "age.key")
        subprocess.run(["age-keygen", "-o", key], capture_output=True, check=True)
        recipient = re.search(r"public key: (age1\S+)", open(key).read()).group(1)
        good = os.path.join(tmp, "good")
        with open(good, "w") as f:
            f.write("Zx9storePASSWORDforADMIN")
        enc = subprocess.run(["sops", "-e", "--age", recipient, "--input-type", "binary",
                              "--output-type", "binary", good], capture_output=True)
        with open(os.path.join(store, "argocd_admin_pass.enc"), "wb") as f:
            f.write(enc.stdout)
        log = os.path.join(tmp, "log")
        lib = os.path.join(ROOT, "lib", "access.sh")
        script = f'source "{lib}"; argocd_admin_login_ok https://argocd.example'
        base = {"PATH": bindir + os.pathsep + os.environ["PATH"], "HOME": tmp,
                "STATE_SECRETS": store, "SOPS_AGE_KEY_FILE": key,
                "FAKE_LOG": log, "FAKE_GOOD": good}
        for mode, want in (("honest", 0), ("rejects", 1), ("anything", 1)):
            open(log, "w").close()
            p = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                               env=dict(base, FAKE_MODE=mode), timeout=60)
            if (p.returncode == 0) != (want == 0):
                what = {"honest": "the store's password is accepted and a made-up one rejected",
                        "rejects": "ArgoCD rejects the store's password",
                        "anything": "ArgoCD accepts ANY password"}[mode]
                findings.append(f"argocd_admin_login_ok {'failed' if want == 0 else 'passed'} when {what}")
            calls = open(log).read()
            if "Zx9storePASSWORDforADMIN" in calls:
                findings.append("argocd_admin_login_ok put the password in curl's argv")
            if "/api/v1/session" not in calls:
                findings.append("argocd_admin_login_ok does not log in at /api/v1/session")
            if "Zx9storePASSWORDforADMIN" in p.stdout + p.stderr:
                findings.append("argocd_admin_login_ok printed the password")
        scope.append("the login helper against an honest, a rejecting and an accept-anything ArgoCD")

for x in findings:
    print(x)
print(f"SCOPE: {'; '.join(scope)}")
