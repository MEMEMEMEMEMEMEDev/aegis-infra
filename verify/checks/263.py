"""Check 263 — every aegis command finds the instance's age key, from any directory.

MEASURED 2026-09-30 on the Arch lab VM: `aegis app new portafolio` run from the
product checkout died at its secrets step — sops looked for the default
~/.config/sops/age/keys.txt, «failed to get the data key». Phase 10 puts
the key at ~/.config/sops/age/aegis.key (ADR-0003) and announces it with a
direnv .envrc in the instance directory, which acts only in an interactive
shell standing there. lib/secrets.sh re-derived it for the bash commands
that source it; the python ones (aegis-secret, aegis-app) never did.

bin/aegis now does it once, for every command. The check RUNS the
dispatcher from / with a probe command that prints what it sees.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
findings = []
with tempfile.TemporaryDirectory() as tmp:
    prod = os.path.join(tmp, "product")
    os.makedirs(os.path.join(prod, "bin"))
    os.makedirs(os.path.join(prod, "libexec"))
    shutil.copy(os.path.join(ROOT, "bin", "aegis"), os.path.join(prod, "bin", "aegis"))
    shutil.copytree(os.path.join(ROOT, "lib"), os.path.join(prod, "lib"))
    probe = os.path.join(prod, "libexec", "aegis-probe")
    with open(probe, "w") as f:
        f.write("#!/usr/bin/env bash\n# aegis-summary: probe\n# aegis-group: dev\nprintf 'KEY=%s\\n' \"${SOPS_AGE_KEY_FILE:-}\"\n")
    os.chmod(probe, 0o755)
    home = os.path.join(tmp, "home")
    keydir = os.path.join(home, ".config", "sops", "age")
    os.makedirs(keydir)
    key = os.path.join(keydir, "aegis.key")
    other = os.path.join(tmp, "elsewhere.key")
    open(other, "w").close()

    def run(env_extra, with_key):
        if with_key and not os.path.exists(key):
            open(key, "w").close()
        if not with_key and os.path.exists(key):
            os.remove(key)
        env = {"PATH": os.environ["PATH"], "HOME": home, "AEGIS_HOME": os.path.join(tmp, "instance")}
        env.update(env_extra)
        p = subprocess.run(["bash", os.path.join(prod, "bin", "aegis"), "probe"], cwd="/",
                           capture_output=True, text=True, env=env, timeout=30)
        for ln in p.stdout.splitlines():
            if ln.startswith("KEY="):
                return ln[4:]
        return f"(no answer, rc {p.returncode}: {p.stderr.strip()[:100]})"

    got = run({}, True)
    if got != key:
        findings.append(f"run from / with the key installed and no variable, a command sees {got!r}: sops falls back to keys.txt (the Arch lab VM, app new)")
    got = run({"SOPS_AGE_KEY_FILE": os.path.join(tmp, "nothing-here.key")}, True)
    if got != key:
        findings.append(f"a SOPS_AGE_KEY_FILE pointing at nothing is kept ({got!r}) instead of the installed key")
    got = run({"SOPS_AGE_KEY_FILE": other}, True)
    if got != other:
        findings.append(f"an explicit SOPS_AGE_KEY_FILE pointing at a real file is overridden ({got!r}): a restore from a backup copy would use the wrong key")
    got = run({}, False)
    if got != "":
        findings.append(f"with no key installed a command is handed {got!r}: a path to nothing reads as a key")

print("SCOPE: bin/aegis run from / with a probe command, 4 cases (installed, dangling variable, explicit variable, none)")
for x in findings:
    print(x)
