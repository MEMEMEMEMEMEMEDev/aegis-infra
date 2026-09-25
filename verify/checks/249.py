"""Check 249 — a service's `secretos:` are listed, and `aegis secret put` is their only door.

2026-09-25: the hackathon's motor needs a cloud key and its hub a panel
password, material the platform cannot invent. `put` is DRIVEN here over a
throwaway instance with a fake `sops` that records its argv and its stdin:
the material must reach sops through stdin, as `data:` of the file's exact
bytes, never in argv or on the screen, and only for a file a contract
declares.
"""
import base64
import os
import subprocess
import sys
import tempfile

import yaml

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []
PLANS = os.path.join(ROOT, "seed", "platform", "plans.yaml")
CONTRACT = """version: 1
organizacion: sala
cuota: pequena
repo: acme/sala
servicios:
  - {nombre: motor, tipo: worker, secretos: [nube]}
"""
FAKE_SOPS = r"""#!/usr/bin/env python3
import sys, os
data = sys.stdin.read()
log = os.environ["FAKE_SOPS_LOG"]
with open(log, "a") as f:
    f.write("ARGV " + " ".join(sys.argv[1:]) + "\n")
    f.write("STDIN\n" + data + "\nEND\n")
import yaml
d = yaml.safe_load(data)
for sec in ("data", "stringData"):
    for k in (d.get(sec) or {}):
        d[sec][k] = "ENC[AES256_GCM,data:fake]"
d["sops"] = {"version": "fake"}
sys.stdout.write(yaml.safe_dump(d, sort_keys=False))
"""

from aegis import org  # noqa: E402

plans = yaml.safe_load(open(PLANS, encoding="utf-8"))
c = org.validate(yaml.safe_load(CONTRACT), plans)
if "secret-motor-nube.enc.yaml" not in org.secrets_of(c):
    findings.append("a service's secretos do not reach the generator: a declared secret is never listed nor reported missing")
for bad, why in [
    (CONTRACT.replace("[nube]", "[credenciales]"), "`credenciales`, the databases' suffix"),
    (CONTRACT.replace("[nube]", "[nube, nube]"), "a secreto declared twice"),
    (CONTRACT.replace("[nube]", "[Nube!]"), "a name that is not a name"),
    (CONTRACT + "  - {nombre: datos, tipo: postgres, secretos: [x1]}\n", "secretos on a provided type"),
]:
    try:
        org.validate(yaml.safe_load(bad), plans)
        findings.append(f"the contract validates with {why}")
    except org.Invalid:
        pass

with tempfile.TemporaryDirectory() as home:
    plat = os.path.join(home, "platform")
    os.makedirs(os.path.join(plat, "orgs"))
    os.makedirs(os.path.join(plat, "k8s", "organizations", "org-sala"))
    open(os.path.join(plat, "plans.yaml"), "w").write(open(PLANS).read())
    open(os.path.join(plat, "orgs", "sala.yaml"), "w").write(CONTRACT)
    bindir = os.path.join(home, "bin")
    os.makedirs(bindir)
    open(os.path.join(bindir, "sops"), "w").write(FAKE_SOPS)
    os.chmod(os.path.join(bindir, "sops"), 0o755)
    log = os.path.join(home, "sops.log")
    material = b'{"type": "service_account", "private_key": "MATERIAL-7f3a9"}\n'
    src = os.path.join(home, "key.json")
    open(src, "wb").write(material)
    empty = os.path.join(home, "empty")
    open(empty, "wb").close()
    # PLATFORM_DIR too: it outranks AEGIS_HOME (paths.platform_dir), and
    # the verify harness exports it pointing at the seed.
    env = dict(os.environ, AEGIS_HOME=home, PLATFORM_DIR=plat,
               PATH=bindir + os.pathsep + os.environ["PATH"], FAKE_SOPS_LOG=log, NO_COLOR="1")
    env.pop("AEGIS_CONF", None)
    target = os.path.join(plat, "k8s", "organizations", "org-sala", "secret-motor-nube.enc.yaml")
    undeclared = os.path.join(plat, "k8s", "organizations", "org-sala", "secret-motor-otra.enc.yaml")

    def put(path, *extra):
        return subprocess.run([os.path.join(ROOT, "bin", "aegis"), "secret", "put", path, *extra],
                              capture_output=True, text=True, env=env, cwd=plat)

    r = put(undeclared, "--from-file", f"key.json={src}")
    if r.returncode == 0 or os.path.exists(undeclared):
        findings.append("put writes a secret no contract declares under secretos")
    r = put(target, "--from-file", f"x={empty}")
    if r.returncode == 0 or os.path.exists(target):
        findings.append("put accepts an empty file as a credential")
    r = put(target, "--from-file", f"key.json={src}")
    if r.returncode != 0 or not os.path.exists(target):
        findings.append(f"put of a declared secret fails (rc {r.returncode}): {(r.stderr or r.stdout).strip()[:160]}")
    else:
        if b"MATERIAL-7f3a9" in (r.stdout + r.stderr).encode():
            findings.append("put prints the material")
        if oct(os.stat(target).st_mode & 0o777) != "0o600":
            findings.append("the encrypted file is not 0600")
        text = open(log).read() if os.path.exists(log) else ""
        argv = "\n".join(l for l in text.splitlines() if l.startswith("ARGV "))
        if "MATERIAL-7f3a9" in argv or base64.b64encode(material).decode() in argv:
            findings.append("the material reaches sops in argv (/proc/PID/cmdline is public)")
        stdin = text.split("STDIN\n", 1)[1].rsplit("\nEND", 1)[0] if "STDIN\n" in text else ""
        doc = yaml.safe_load(stdin) if stdin else {}
        if (doc or {}).get("stringData"):
            findings.append("the material goes as stringData: a folded or trimmed value is another credential")
        got = ((doc or {}).get("data") or {}).get("key.json")
        if got is None or base64.b64decode(got) != material:
            findings.append("the Secret's data is not the file's exact bytes (trailing newline included)")
        meta = (doc or {}).get("metadata") or {}
        if meta.get("name") != "motor-nube" or meta.get("namespace") != "org-sala":
            findings.append(f"the Secret is named {meta.get('name')}/{meta.get('namespace')}, not motor-nube in org-sala")
        # The fake sops writes the same envelope whatever the material, so
        # the FILE cannot tell a re-encryption apart: count sops's calls.
        calls = open(log).read().count("ARGV ")
        other = os.path.join(home, "other.json")
        open(other, "wb").write(b'{"a different": "key"}\n')
        r2 = put(target, "--from-file", f"key.json={other}")
        if r2.returncode != 0 or open(log).read().count("ARGV ") != calls:
            findings.append("a second put without --replace changes (or refuses) the existing secret instead of leaving it")

for f in findings:
    print(f)
print("SCOPE: secretos rendered and refused four ways; put driven over a fake sops (argv, stdin, bytes, gate, idempotence)")
