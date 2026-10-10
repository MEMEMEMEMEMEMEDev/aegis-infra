"""Check 277 — the edge's plaintext state does not outlive a wrapper call.

MEASURED 2026-10-09 on the home instance: terraform.tfstate and its
.backup had been sitting in envs/cloudflare-tunnel since 25-09 —600,
ignored by git, but with the tunnel's token and the Access service
token's secret in the clear— and one `grep` over the tofu tree printed
both into an agent's transcript. The encrypted copy is the truth (#46)
and the wrapper decrypts it on every call, so the plaintext is a working
file of the call.

Driven: the wrapper is copied into a sandbox with a fake tofu that writes
state the way the binary does (the state, its .backup, and a numbered
backup) and a real sops + age with a key made for the run. Asserted:
  · after an apply, no plaintext state nor backup is left, and the
    encrypted copy decrypts to the state the apply wrote;
  · a read call (`output -raw`) still answers on stdout, and leaves
    nothing behind;
  · a plaintext state with no encrypted twin (an instance from before
    #46) is encrypted and then shredded — never shredded unencrypted;
  · without the age key to prove the copy, the plaintext is LEFT, and
    the wrapper says so;
  · nothing of the state reaches the screen.
Read, comment-stripped: `aegis destroy`, `aegis state backup|restore`
and `aegis rotate` look at the encrypted copy, not at the plaintext that
is no longer there.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
WRAPPER = os.path.join(ROOT, "seed", "platform", "tofu", "tofu-apply.sh")
SECRET = "z7Kq2TUNNELsecretINtheCLEAR"
findings = []
scope = []


def code(path):
    """The file without its comment lines: prose is not code."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        findings.append(f"{os.path.relpath(path, ROOT)} is missing")
        return ""
    return "\n".join(l for l in text.splitlines() if not re.match(r"^\s*#", l))


# A tofu that writes state the way the binary does: on apply, the old state
# goes to .backup (and a numbered backup, as `state rm` leaves), and the new
# one —one serial up— to terraform.tfstate. `output -raw` reads the state.
FAKE = r'''#!/bin/sh
for a in "$@"; do case "$a" in -chdir=*) cd "${a#-chdir=}" || exit 9 ;; esac; done
for a in "$@"; do case "$a" in -*) ;; *) sub="$a"; break ;; esac; done
case "$sub" in
  apply)
    serial=0
    if [ -f terraform.tfstate ]; then
      serial="$(python3 -c 'import json; print(json.load(open("terraform.tfstate"))["serial"])')"
      cp terraform.tfstate terraform.tfstate.backup
      cp terraform.tfstate terraform.tfstate.1790000000.backup
    fi
    serial=$((serial + 1))
    printf '{"version": 4, "serial": %s, "outputs": {"tunnel_token": {"value": "%s"}}, "resources": []}\n' \
      "$serial" "$FAKE_SECRET" > terraform.tfstate
    echo "Apply complete! Resources: 0 added, 1 changed, 0 destroyed."
    ;;
  output)
    python3 -c 'import json,sys; sys.stdout.write(json.load(open("terraform.tfstate"))["outputs"]["tunnel_token"]["value"])'
    ;;
esac
exit 0
'''

for tool in ("sops", "age-keygen", "shred"):
    if not shutil.which(tool):
        findings.append(f"`{tool}` is not on this machine: the shredding cannot be driven here")

if not findings:
    with tempfile.TemporaryDirectory() as tmp:
        platform = os.path.join(tmp, "platform")
        tofu_dir = os.path.join(platform, "tofu")
        env_dir = os.path.join(tofu_dir, "envs", "t")
        os.makedirs(env_dir)
        shutil.copy(WRAPPER, os.path.join(tofu_dir, "tofu-apply.sh"))
        with open(os.path.join(env_dir, "variables.tf"), "w") as f:
            f.write('variable "cloudflare_api_token" {\n  type = string\n}\n')
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        with open(os.path.join(bindir, "tofu"), "w") as f:
            f.write(FAKE)
        os.chmod(os.path.join(bindir, "tofu"), 0o755)
        key = os.path.join(tmp, "age.key")
        subprocess.run(["age-keygen", "-o", key], capture_output=True, check=True)
        recipient = re.search(r"public key: (age1\S+)", open(key).read()).group(1)
        with open(os.path.join(platform, ".sops.yaml"), "w") as f:
            f.write("creation_rules:\n"
                    "  - path_regex: tofu/envs/.*/terraform\\.tfstate\\.enc\\.json$\n"
                    f"    age: {recipient}\n")

        plain = os.path.join(env_dir, "terraform.tfstate")
        enc = plain + ".enc.json"
        base = {"HOME": tmp, "TF_VAR_cloudflare_api_token": "t", "FAKE_SECRET": SECRET,
                "AEGIS_INIT_CONF": os.path.join(tmp, "none"),
                "PATH": bindir + os.pathsep + os.environ["PATH"]}
        keyed = dict(base, SOPS_AGE_KEY_FILE=key)

        def run(*args, env=keyed):
            return subprocess.run(["bash", os.path.join(tofu_dir, "tofu-apply.sh"), "-chdir=envs/t", *args],
                                  capture_output=True, text=True, env=env, cwd=tofu_dir, timeout=120)

        def leftovers():
            return sorted(n for n in os.listdir(env_dir)
                          if n.startswith("terraform.tfstate") and not n.endswith(".enc.json"))

        def decrypted():
            p = subprocess.run(["sops", "-d", "--output-type", "json", enc], capture_output=True,
                               text=True, env=keyed, timeout=60)
            return json.loads(p.stdout) if p.returncode == 0 else None

        # 1. the first apply: no encrypted state yet
        p = run("apply", "-auto-approve")
        if SECRET in p.stdout + p.stderr:
            findings.append("an apply put a value of the state on the screen")
        if p.returncode != 0:
            findings.append(f"the first apply exited {p.returncode}: {p.stderr.strip()[-160:]}")
        if not os.path.isfile(enc):
            findings.append("the first apply left no encrypted state")
        if leftovers():
            findings.append(f"after an apply, plaintext state is left on disk: {', '.join(leftovers())}")
        st = decrypted() if os.path.isfile(enc) else None
        if not st or st.get("serial") != 1:
            findings.append("the encrypted copy does not hold the state the first apply wrote")
        scope.append("a first apply")

        # 2. a second apply: tofu writes .backup and a numbered backup
        p = run("apply", "-auto-approve")
        if leftovers():
            findings.append(f"after a second apply, tofu's backups are left with the old state in the clear: {', '.join(leftovers())}")
        st = decrypted()
        if not st or st.get("serial") != 2:
            findings.append("the encrypted copy did not follow the second apply: the state went back a serial")
        scope.append("an apply over an existing state, with its backups")

        # 3. a read: stdout is sacred, and it leaves nothing
        p = run("output", "-raw", "tunnel_token")
        if p.stdout != SECRET:
            findings.append(f"`output -raw` no longer answers on stdout (phase 25 captures it): {p.stdout[:20]!r}")
        if leftovers():
            findings.append(f"a read call left the decrypted state on disk: {', '.join(leftovers())}")
        scope.append("a read (output -raw)")

        # 4. an instance from before #46: plaintext, no encrypted twin, key at hand
        os.remove(enc)
        with open(plain, "w") as f:
            json.dump({"version": 4, "serial": 7, "outputs": {"tunnel_token": {"value": SECRET}},
                       "resources": []}, f)
        p = run("output", "-raw", "tunnel_token")
        st = decrypted() if os.path.isfile(enc) else None
        if not st or st.get("serial") != 7:
            findings.append("a plaintext state with no encrypted twin was not encrypted first: "
                            "shredding it would lose the edge's only state")
        if os.path.isfile(enc) and leftovers():
            findings.append("a plaintext state from before #46, once encrypted, was left in the clear")
        scope.append("a plaintext state from before #46")

        # 5. no age key to prove the copy: the plaintext stays, and it is said
        if os.path.isfile(enc):
            os.remove(enc)
        with open(plain, "w") as f:
            json.dump({"version": 4, "serial": 9, "outputs": {"tunnel_token": {"value": SECRET}},
                       "resources": []}, f)
        p = run("output", "-raw", "tunnel_token", env=base)
        if not os.path.isfile(plain):
            findings.append("without the age key to prove the encrypted copy, the plaintext was shredded anyway: "
                            "an unproven copy is not a copy")
        elif "LEFT" not in p.stderr:
            findings.append("the plaintext was left without a word: nobody learns the secrets are still in the clear")
        scope.append("no age key to prove the copy")

# ── read: the callers look at the encrypted copy ─────────────────────────
destroy = code(os.path.join(ROOT, "libexec", "aegis-destroy"))
m = re.search(r'if \[\[([^\n]*)\]\]; then\s*\n\s*say "cloudflare-tunnel: init of the env', destroy)
if not m or "terraform.tfstate.enc.json" not in m.group(1):
    findings.append("`aegis destroy` decides whether there is an edge to destroy by the PLAINTEXT state, "
                    "which no longer exists: it would leave the whole edge standing in Cloudflare")

backup = code(os.path.join(ROOT, "libexec", "state", "backup"))
m = re.search(r"^collect tfstate\s+(.*)$", backup, re.M)
if not m or "terraform.tfstate.enc.json" not in m.group(1):
    findings.append("`aegis state backup` collects only the plaintext state: the bundle would carry no edge state")

restore = code(os.path.join(ROOT, "libexec", "state", "restore"))
m = re.search(r"place_tfstate\(\)\s*\{(.*?)\n\}", restore, re.S)
if not m:
    findings.append("`aegis state restore` has no guard of its own for the edge's state")
else:
    body = m.group(1)
    if not re.search(r"cmp -s [^\n]*\|\|\s*clash=", body):
        findings.append("`aegis state restore` refuses the edge's state just for existing (a clone of the "
                        "platform repo always has it) or overwrites it without comparing: it must refuse "
                        "only a copy that says something else")
    if "FORCE" not in body:
        findings.append("`aegis state restore` overwrites a differing edge state without --force")
if not re.search(r"^\s*place_tfstate\s*$", restore, re.M):
    findings.append("`aegis state restore` defines the edge-state guard but never calls it")

rotate = code(os.path.join(ROOT, "libexec", "aegis-rotate"))
m = re.search(r'\[\[ "\$1" == "tunnel_token" \]\] && \\\s*\n\s*f="([^"]*)"', rotate)
if not m or not m.group(1).endswith("terraform.tfstate.enc.json"):
    findings.append("`aegis rotate` dates the tunnel token by the plaintext state, which no longer exists: "
                    "its age would read «?»")

for x in findings:
    print(x)
print(f"SCOPE: the wrapper driven over {'; '.join(scope) or 'nothing'} with a real sops and age; "
      "destroy, backup, restore and rotate read")
