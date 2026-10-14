"""Check 283 — a Secret is encrypted before it enters the platform repo, and
a cleartext one under an encrypted name is never committed.

REVIEW of 2026-10-13 (A-3), read in lib/secrets.sh: make_enc_secret wrote
the Secret in tmpfs, MOVED the plaintext into the platform checkout (so
that .sops.yaml's path_regex would match the destination) and only then
ran `sops -e --in-place`. Phase 15 did the same with the Cloudflare
tokens. A sops that fails between the two (no key in the environment, a
rule that does not match, a Ctrl-C) leaves a cleartext Secret under a
*.enc.yaml name inside a git checkout; the phase dies, the operator
resumes with --from, and the next phase's `git add -A … commit
--no-verify` carries it to GitHub, where a force push does not un-publish
a blob.

Read, comment-stripped:
  · sops_encrypt_repo passes --filename-override, so a file in tmpfs is
    encrypted under the rule of the path it is bound for;
  · make_enc_secret encrypts BEFORE it moves, and hands the helper the
    destination; phase 15's token block does the same;
  · git_commit_if_changes reads what is staged and refuses a *.enc.yaml
    or *.enc.json that carries no sops metadata.
Driven, with a real sops and age over a throwaway key, a fake kubectl and
a sandbox git repo:
  · make_enc_secret lands an encrypted Secret that decrypts to what was
    given, and the plaintext bytes are nowhere in the checkout;
  · with a sops that refuses to encrypt, make_enc_secret dies and NOTHING
    exists at the destination (the regression's exact shape);
  · git_commit_if_changes dies on a staged cleartext *.enc.yaml and on a
    cleartext *.enc.json, commits a real ciphertext, and lets a staged
    deletion of an .enc.yaml through.
"""
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
# the instance's variables never reach the sandbox: the verifier runs with
# the operator's AEGIS_* exported, and a driver that inherits them writes
# into the live instance (a gates.jsonl under ~/aegis, 2026-10-14)
_clean = {k: v for k, v in os.environ.items()
          if not (k.startswith("AEGIS_") or k in ("PLATFORM_DIR", "SOPS_AGE_KEY_FILE", "AGE_PUBLIC"))}
findings = []
scope = []


def code(rel):
    """The file without its comment lines: prose is not code."""
    try:
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    except OSError:
        findings.append(f"{rel} is missing")
        return ""
    return "\n".join(l for l in text.splitlines() if not re.match(r"^\s*#", l))


def body_of(fn, text):
    """What verify/lib.sh's body_of gives: from `fn() {` to the `}` in column 0."""
    lines = text.splitlines()
    out, inside = [], False
    for l in lines:
        if not inside and l.startswith(fn + "()"):
            inside = True
        if inside:
            out.append(l)
            if l.startswith("}"):
                break
    return "\n".join(out)


# ── read ─────────────────────────────────────────────────────────────────
sec = code("lib/secrets.sh")
helper = body_of("sops_encrypt_repo", sec)
if not helper:
    findings.append("lib/secrets.sh has no sops_encrypt_repo")
if "--filename-override" not in helper:
    findings.append("sops_encrypt_repo does not pass --filename-override: a file in tmpfs cannot be "
                    "encrypted under the destination's rule, so the plaintext has to visit the repo first")
if "--config" not in helper:
    findings.append("sops_encrypt_repo lost its explicit --config (pattern A)")

mes = body_of("make_enc_secret", sec)
i_enc = mes.find("sops_encrypt_repo ")
i_mv = mes.find('mv "$tmp_yaml" "$dest"')
if i_enc < 0 or i_mv < 0:
    findings.append("make_enc_secret no longer encrypts through sops_encrypt_repo and moves with mv: "
                    "re-aim this check")
elif i_mv < i_enc:
    findings.append("make_enc_secret moves the PLAINTEXT into the repo before encrypting it: a sops "
                    "that fails in between leaves a cleartext Secret under a *.enc.yaml name in the "
                    "checkout")
elif 'sops_encrypt_repo "$tmp_yaml" "$dest"' not in mes:
    findings.append("make_enc_secret does not hand sops_encrypt_repo the destination whose rule "
                    "applies to the tmpfs file")
scope.append("make_enc_secret and sops_encrypt_repo read")

p15 = code("init/phases/15-third-parties.sh")
t_enc = p15.find('sops_encrypt_repo "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"')
t_mv = p15.find('mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"')
if t_enc < 0 or t_mv < 0 or t_mv < t_enc:
    findings.append("phase 15 moves the Cloudflare tokens into the repo before encrypting them (or "
                    "no longer encrypts them in tmpfs under tofu/secrets' rule)")
scope.append("phase 15's token block read")

com = code("lib/common.sh")
guard = body_of("git_commit_if_changes", com)
if "diff --cached --name-only" not in guard:
    findings.append("git_commit_if_changes commits whatever is staged without looking at it")
for suffix in (".enc.yaml", ".enc.json"):
    if suffix not in guard:
        findings.append(f"git_commit_if_changes does not look at staged {suffix} files: a cleartext "
                        f"one would be committed")
if not re.search(r'sops"?\??:', guard) or not re.search(r'mac"?\??:', guard):
    findings.append("git_commit_if_changes does not ask a staged encrypted-named file for sops "
                    "metadata (the `sops:` block and its `mac:`)")
if "die " not in guard:
    findings.append("git_commit_if_changes does not die on a cleartext secret: it warns at best")
scope.append("git_commit_if_changes read")

# ── drive ────────────────────────────────────────────────────────────────
FAKE_KUBECTL = r'''#!/usr/bin/env python3
# a kubectl that renders `create secret generic` the way the binary does
# with --dry-run=client -o yaml: data: with base64 of each --from-file.
import base64, sys
a = sys.argv[1:]
if a[:3] != ["create", "secret", "generic"]:
    sys.stderr.write("fake kubectl: only `create secret generic` is served\n"); sys.exit(7)
name, ns, typ, data = a[3], None, None, []
for i, x in enumerate(a):
    if x == "-n": ns = a[i + 1]
    if x.startswith("--type="): typ = x[len("--type="):]
    if x.startswith("--from-file="):
        k, _, path = x[len("--from-file="):].partition("=")
        data.append((k, base64.b64encode(open(path, "rb").read()).decode()))
out = ["apiVersion: v1", "data:"] + [f"  {k}: {v}" for k, v in data] + \
      ["kind: Secret", "metadata:", "  creationTimestamp: null", f"  name: {name}", f"  namespace: {ns}"]
if typ: out.append(f"type: {typ}")
print("\n".join(out))
'''
FAKE_SOPS = '''#!/bin/sh
# a sops that refuses to encrypt and does everything else for real
for a in "$@"; do case "$a" in -e|--encrypt) echo "fake sops: encryption refused" >&2; exit 1 ;; esac; done
exec "$REAL_SOPS" "$@"
'''
VALUE = "Qf3hPROBE283value"          # fabricated here, never persisted beyond the sandbox
B64 = base64.b64encode(VALUE.encode()).decode()

for tool in ("sops", "age-keygen", "git"):
    if not shutil.which(tool):
        findings.append(f"`{tool}` is not on this machine: the helpers cannot be driven here")

if all(shutil.which(t) for t in ("sops", "age-keygen", "git")):
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "bin")
        home = os.path.join(tmp, "home")
        plat = os.path.join(home, "platform")
        os.makedirs(bindir)
        os.makedirs(os.path.join(plat, "k8s", "base", "x"))
        with open(os.path.join(bindir, "kubectl"), "w") as f:
            f.write(FAKE_KUBECTL)
        os.chmod(os.path.join(bindir, "kubectl"), 0o755)
        key = os.path.join(tmp, "age.key")
        subprocess.run(["age-keygen", "-o", key], capture_output=True, check=True)
        recipient = re.search(r"public key: (age1\S+)", open(key).read()).group(1)
        with open(os.path.join(plat, ".sops.yaml"), "w") as f:
            f.write("creation_rules:\n"
                    "  - path_regex: k8s/.*\\.enc\\.yaml$\n"
                    "    encrypted_regex: ^(data|stringData)$\n"
                    f"    age: {recipient}\n"
                    "  - path_regex: tofu/envs/.*/terraform\\.tfstate\\.enc\\.json$\n"
                    f"    age: {recipient}\n")
        subprocess.run(["git", "init", "-q", plat], check=True)
        subprocess.run(["git", "-C", plat, "config", "user.email", "probe@example.invalid"], check=True)
        subprocess.run(["git", "-C", plat, "config", "user.name", "probe"], check=True)
        dest = os.path.join(plat, "k8s", "base", "x", "secret-demo.enc.yaml")
        env = dict(_clean, PATH=bindir + os.pathsep + os.environ["PATH"], HOME=home,
                   AEGIS_ROOT=ROOT, AEGIS_HOME=home, PLATFORM_DIR=plat, SOPS_AGE_KEY_FILE=key,
                   CHECK_MODE="false", AEGIS_NONINTERACTIVE="false", REAL_SOPS=shutil.which("sops"),
                   PROBE_VALUE=VALUE, PROBE_DEST=dest)
        preamble = ('set -euo pipefail; source "$AEGIS_ROOT/lib/common.sh"; '
                    'source "$AEGIS_ROOT/lib/secrets.sh"; ')

        def run(script, extra_path=None):
            e = dict(env)
            if extra_path:
                e["PATH"] = extra_path + os.pathsep + e["PATH"]
            return subprocess.run(["bash", "-c", preamble + script], capture_output=True,
                                  text=True, env=e, timeout=120)

        def commits():
            r = subprocess.run(["git", "-C", plat, "rev-list", "--count", "HEAD"],
                               capture_output=True, text=True)
            return int(r.stdout.strip() or 0) if r.returncode == 0 else 0

        # (a) the happy path: an encrypted Secret lands, decrypts, and the plaintext is nowhere
        p = run('secrets_workdir; printf "%s" "$PROBE_VALUE" > "$SECRETS_TMP/password"; '
                'make_enc_secret demo ns "$PROBE_DEST" "password=$SECRETS_TMP/password"')
        if p.returncode != 0:
            findings.append(f"make_enc_secret failed on the happy path (rc {p.returncode}): "
                            f"{(p.stderr or p.stdout)[-200:]!r}")
        elif not os.path.exists(dest):
            findings.append("make_enc_secret ended green and left nothing at the destination")
        else:
            txt = open(dest).read()
            if not re.search(r"^sops:", txt, re.M) or not re.search(r"^\s+mac:", txt, re.M):
                findings.append("the file make_enc_secret left at the destination carries no sops metadata")
            if B64 in txt or VALUE in txt:
                findings.append("the plaintext value sits in the file at the destination")
            d = subprocess.run(["sops", "-d", dest], capture_output=True, text=True, env=env)
            if d.returncode != 0 or f"password: {B64}" not in d.stdout:
                findings.append("the file at the destination does not decrypt to the Secret that was given")
            leak = subprocess.run(["grep", "-rl", VALUE, plat], capture_output=True, text=True)
            if leak.stdout.strip():
                findings.append("the plaintext value is somewhere in the checkout: "
                                f"{leak.stdout.strip().replace(plat + '/', '')}")
        if VALUE in (p.stdout + p.stderr):
            findings.append("make_enc_secret printed the secret's value")
        scope.append("make_enc_secret driven with a real sops and age (happy path)")

        # (b) the regression's shape: sops refuses to encrypt → die, and NOTHING at the destination
        failbin = os.path.join(tmp, "failbin")
        os.makedirs(failbin)
        with open(os.path.join(failbin, "sops"), "w") as f:
            f.write(FAKE_SOPS)
        os.chmod(os.path.join(failbin, "sops"), 0o755)
        dest2 = os.path.join(plat, "k8s", "base", "x", "secret-dies.enc.yaml")
        env["PROBE_DEST2"] = dest2
        p = run('secrets_workdir; printf "%s" "$PROBE_VALUE" > "$SECRETS_TMP/password"; '
                'make_enc_secret dies ns "$PROBE_DEST2" "password=$SECRETS_TMP/password"',
                extra_path=failbin)
        if p.returncode == 0:
            findings.append("make_enc_secret ended green although sops refused to encrypt")
        if os.path.exists(dest2):
            findings.append("with sops refusing to encrypt, a file was left at the destination: "
                            "that is the plaintext Secret under an encrypted name")
        scope.append("make_enc_secret driven with a sops that refuses (nothing left at the destination)")

        # (c) the fence: a cleartext *.enc.yaml staged → die, no commit
        clear = os.path.join(plat, "k8s", "base", "x", "secret-clear.enc.yaml")
        with open(clear, "w") as f:
            f.write("apiVersion: v1\nkind: Secret\nmetadata:\n  name: clear\n  namespace: ns\n"
                    f"data:\n  password: {B64}\n")
        before = commits()
        p = run('git_commit_if_changes "$PLATFORM_DIR" "probe: a cleartext secret"')
        if p.returncode == 0 or commits() != before:
            findings.append("git_commit_if_changes committed a cleartext Secret staged under an "
                            "encrypted name")
        os.remove(clear)
        # (d) the fence lets the real ciphertext through
        if os.path.exists(dest):
            p = run('git_commit_if_changes "$PLATFORM_DIR" "probe: the ciphertext"')
            if p.returncode != 0 or commits() != before + 1:
                findings.append("git_commit_if_changes refused a Secret sops really encrypted "
                                f"(rc {p.returncode}): {(p.stderr or p.stdout)[-160:]!r}")
        # (e) a cleartext tofu state under .enc.json is refused too
        tfdir = os.path.join(plat, "tofu", "envs", "probe")
        os.makedirs(tfdir)
        tf = os.path.join(tfdir, "terraform.tfstate.enc.json")
        with open(tf, "w") as f:
            f.write('{"version": 4, "resources": [{"token": "' + VALUE + '"}]}\n')
        before = commits()
        p = run('git_commit_if_changes "$PLATFORM_DIR" "probe: a cleartext state"')
        if p.returncode == 0 or commits() != before:
            findings.append("git_commit_if_changes committed a cleartext tofu state staged under "
                            "an encrypted name (.enc.json)")
        os.remove(tf)
        # (f) a staged deletion of an .enc.yaml does not trip the fence
        if os.path.exists(dest) and commits() >= 1:
            subprocess.run(["git", "-C", plat, "rm", "-q", dest], check=False)
            before = commits()
            p = run('git_commit_if_changes "$PLATFORM_DIR" "probe: the deletion"')
            if p.returncode != 0 or commits() != before + 1:
                findings.append("git_commit_if_changes refuses a staged DELETION of an .enc.yaml: "
                                "a secret could never be retired")
        scope.append("git_commit_if_changes driven: cleartext yaml refused, cleartext json refused, "
                     "ciphertext committed, deletion committed")

print("SCOPE: " + "; ".join(scope))
for f in findings:
    print(f)
