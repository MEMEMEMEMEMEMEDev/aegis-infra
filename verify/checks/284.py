"""Check 284 — a secret that fails to generate stops the init, and empty
material never reaches the store.

REVIEW of 2026-10-13 (A-4). bash turns errexit OFF inside a command
substitution unless `shopt -s inherit_errexit` is set, and nothing in the
product set it. The whole secrets mechanism runs generators inside
`out="$(gen_hex32 name)"`: a failing openssl (absent, out of entropy, a
ulimit) was shrugged off, the function logged «generated (0 bytes)» and
returned the path of an EMPTY file, persist_secret encrypted it, the
roundtrip compared empty with empty and passed, and the store restored
that empty HMAC on every re-run — registered with GitHub, failing every
delivery with a 400 nobody could explain. Reproduced on bash 5.2:
`f() { false | tr -d x > out; echo out; }; x=$(f); echo alive` prints
alive under `set -euo pipefail`.

Read, comment-stripped: every lib that sets errexit sets inherit_errexit
with it; persist_secret refuses empty material before it encrypts; each
generator checks the size of what it produced through _gen_guard, which
dies.
Driven: the bash semantics themselves (a function whose pipeline fails
inside `$( )` must not let the caller go on); gen_hex32 with an openssl
that fails, and with one that succeeds with nothing; persist_secret with
an empty file; gen_or_restore end to end with the failing openssl (no
file in the store afterwards); the happy path with the real openssl and a
real sops + age (64 bytes, persisted, restored byte-identical).
"""
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
LIBS = ("lib/common.sh", "lib/secrets.sh", "lib/jenkins.sh", "lib/checks.sh", "lib/config.sh")


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
for rel in LIBS:
    t = code(rel)
    if re.search(r"^set -e", t, re.M) and not re.search(r"^shopt -s inherit_errexit", t, re.M):
        findings.append(f"{rel} sets errexit and not inherit_errexit: inside every `$( )` of what "
                        "sources it, a failing command is still shrugged off")
scope.append(f"{len(LIBS)} libs read")

sec = code("lib/secrets.sh")
ps = body_of("persist_secret", sec)
i_guard, i_enc = ps.find('-s "$src"'), ps.find("--encrypt")
if i_guard < 0:
    findings.append("persist_secret does not refuse an empty file: a failed generator's 0 bytes would "
                    "be encrypted, roundtripped and restored on every re-run")
elif i_enc >= 0 and i_enc < i_guard:
    findings.append("persist_secret looks at the size of the material only after encrypting it")
gg = body_of("_gen_guard", sec)
if not gg:
    findings.append("lib/secrets.sh has no _gen_guard: no generator checks the size of what it produced")
elif "die " not in gg:
    findings.append("_gen_guard does not die on short material: it warns at best")
for fn, want in (("gen_hex32", "64"), ("gen_password_b64", "44"), ("gen_ssh_keypair", "1"),
                 ("gen_age_key", "1")):
    b = body_of(fn, sec)
    if not re.search(r"_gen_guard\s+\S+\s+" + want + r"\b", b):
        findings.append(f"{fn} does not check that it produced at least {want} byte(s)")
scope.append("persist_secret and four generators read")

# ── drive ────────────────────────────────────────────────────────────────
FAKE_OPENSSL_FAILS = '''#!/bin/sh
# an openssl whose `rand` fails, as one does with no entropy or no binary
for a in "$@"; do case "$a" in rand) echo "fake openssl: rand refused" >&2; exit 1 ;; esac; done
exec "$REAL_OPENSSL" "$@"
'''
FAKE_OPENSSL_EMPTY = '''#!/bin/sh
# an openssl whose `rand` succeeds and prints nothing
for a in "$@"; do case "$a" in rand) exit 0 ;; esac; done
exec "$REAL_OPENSSL" "$@"
'''
for tool in ("sops", "age-keygen", "openssl"):
    if not shutil.which(tool):
        findings.append(f"`{tool}` is not on this machine: the generators cannot be driven here")

if all(shutil.which(t) for t in ("sops", "age-keygen", "openssl")):
    with tempfile.TemporaryDirectory() as tmp:
        home = os.path.join(tmp, "home")
        store = os.path.join(home, ".state-secrets")
        os.makedirs(store)
        key = os.path.join(tmp, "age.key")
        subprocess.run(["age-keygen", "-o", key], capture_output=True, check=True)
        recipient = re.search(r"public key: (age1\S+)", open(key).read()).group(1)
        fails, empty = os.path.join(tmp, "fails"), os.path.join(tmp, "empty")
        for d, body in ((fails, FAKE_OPENSSL_FAILS), (empty, FAKE_OPENSSL_EMPTY)):
            os.makedirs(d)
            with open(os.path.join(d, "openssl"), "w") as f:
                f.write(body)
            os.chmod(os.path.join(d, "openssl"), 0o755)
        env = dict(_clean, HOME=home, AEGIS_ROOT=ROOT, AEGIS_HOME=home, STATE_SECRETS=store,
                   SOPS_AGE_KEY_FILE=key, AGE_PUBLIC=recipient, CHECK_MODE="false",
                   AEGIS_NONINTERACTIVE="false", REAL_OPENSSL=shutil.which("openssl"))
        preamble = ('set -euo pipefail; source "$AEGIS_ROOT/lib/common.sh"; '
                    'source "$AEGIS_ROOT/lib/secrets.sh"; secrets_workdir; ')

        def run(script, bindir=None, pre=preamble):
            e = dict(env)
            if bindir:
                e["PATH"] = bindir + os.pathsep + e["PATH"]
            return subprocess.run(["bash", "-c", pre + script], capture_output=True, text=True,
                                  env=e, timeout=120)

        def in_store(name):
            return os.path.exists(os.path.join(store, name + ".enc"))

        # (a) the bash semantics: a pipeline that fails inside $( ) must not let the caller go on
        p = run('f() { false | cat; echo alive; }; x="$(f)"; echo survived',
                pre='set -euo pipefail; source "$AEGIS_ROOT/lib/common.sh"; ')
        if p.returncode == 0 or "survived" in p.stdout:
            findings.append("with lib/common.sh sourced, a function whose pipeline fails inside `$( )` "
                            "still lets its caller carry on: errexit does not reach substitutions")
        # (b) lib/secrets.sh sourced on its own carries the option too
        p = run('shopt -q inherit_errexit',
                pre='source "$AEGIS_ROOT/lib/secrets.sh"; ')
        if p.returncode != 0:
            findings.append("lib/secrets.sh sourced on its own leaves inherit_errexit off")
        scope.append("the bash semantics driven")

        # (c) gen_hex32 with an openssl that fails: no path returned, the caller stops
        p = run('out="$(gen_hex32 probe_fails)"; echo "returned:$out"', bindir=fails)
        if p.returncode == 0 or "returned:" in p.stdout:
            findings.append("gen_hex32 returned a path although openssl failed: the caller would go on "
                            "with an empty secret")
        # (d) gen_hex32 with an openssl that succeeds with nothing: the size guard stops it
        p = run('out="$(gen_hex32 probe_empty)"; echo "returned:$out"', bindir=empty)
        if p.returncode == 0 or "returned:" in p.stdout:
            findings.append("gen_hex32 returned a 0-byte file as a secret, and said nothing")
        # (e) persist_secret refuses an empty file
        p = run(': > "$SECRETS_TMP/nothing"; persist_secret probe_nothing "$SECRETS_TMP/nothing"')
        if p.returncode == 0 or in_store("probe_nothing"):
            findings.append("persist_secret encrypted and kept a 0-byte file")
        # (f) the end-to-end regression: gen_or_restore with the failing openssl leaves no store entry
        p = run('v="$(gen_or_restore probe_e2e gen_hex32)"; echo "returned:$v"', bindir=fails)
        if p.returncode == 0 or "returned:" in p.stdout or in_store("probe_e2e"):
            findings.append("gen_or_restore with a failing openssl ended green or left a file in the "
                            "store: the empty HMAC of the review, persisted")
        scope.append("gen_hex32, persist_secret and gen_or_restore driven with a failing and an empty openssl")

        # (g) the happy path, with the real openssl and a real sops + age
        p = run('out="$(gen_or_restore probe_ok gen_hex32)"; wc -c < "$out"; '
                'r="$(restore_secret probe_ok probe_ok_again)"; cmp -s "$out" "$r" && echo same')
        lines = p.stdout.split()
        if p.returncode != 0 or "64" not in lines or "same" not in lines or not in_store("probe_ok"):
            findings.append(f"the happy path broke (rc {p.returncode}): gen_or_restore did not produce "
                            f"64 bytes, persist them and restore them byte-identical: "
                            f"{(p.stderr or p.stdout)[-160:]!r}")
        scope.append("the happy path driven with the real openssl, sops and age")

print("SCOPE: " + "; ".join(scope))
for f in findings:
    print(f)
