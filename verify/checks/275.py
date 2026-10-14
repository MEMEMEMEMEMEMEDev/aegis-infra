"""Check 275 — --help after a verb is help, and writes nothing.

FOUND on the Debian lab VM, 2026-10-02: `aegis state backup --help` wrote a real
encrypted bundle to a file named «--help». The commands that hand a verb
to a script of its own (`exec libexec/<cmd>/$VERB`) only looked at the word
BEFORE the verb, so the verb's script read «--help» as its first argument.
`aegis dev seed --help` had the same shape.

Derived from the tree, never listed: every libexec/aegis-* that execs a
verb script is found, its verbs are read from its own `case`, and each
`<cmd> <verb> --help` is RUN in an empty directory with HOME pointing at
it: rc 0, a usage on the screen, and not one file created. And a backup
output that starts with «-» is refused (rc 3) instead of written.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
LIBEXEC = os.path.join(ROOT, "libexec")
findings = []
runs = 0

for name in sorted(os.listdir(LIBEXEC)):
    path = os.path.join(LIBEXEC, name)
    if not name.startswith("aegis-") or not os.path.isfile(path):
        continue
    src = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r'exec "\$AEGIS_ROOT/libexec/([a-z-]+)/\$VERB"', src)
    if not m:
        continue
    cmd = name[len("aegis-"):]
    case = re.search(r"^\s*([a-z|-]+)\)\s*VERB=\"\$1\"", src, re.M)
    if not case:
        findings.append(f"{name} execs a verb script and its verbs cannot be read from its case: re-aim this check")
        continue
    for verb in case.group(1).split("|"):
        with tempfile.TemporaryDirectory() as tmp:
            env = {"PATH": os.environ["PATH"], "HOME": tmp, "AEGIS_HOME": os.path.join(tmp, "aegis")}
            p = subprocess.run([os.path.join(ROOT, "bin", "aegis"), cmd, verb, "--help"], cwd=tmp,
                               capture_output=True, text=True, env=env, timeout=60)
            runs += 1
            made = [f for f in os.listdir(tmp)]
            if p.returncode != 0 or "usage" not in (p.stdout + p.stderr).lower():
                findings.append(f"`aegis {cmd} {verb} --help` exits {p.returncode} without a usage: --help after the verb is read as an argument")
            if made:
                findings.append(f"`aegis {cmd} {verb} --help` created {made} — it ran instead of answering")

with tempfile.TemporaryDirectory() as tmp:
    env = {"PATH": os.environ["PATH"], "HOME": tmp, "AEGIS_HOME": os.path.join(tmp, "aegis")}
    p = subprocess.run(["bash", os.path.join(LIBEXEC, "state", "backup"), "--quiet"], cwd=tmp,
                       capture_output=True, text=True, env=dict(env, AEGIS_ROOT=ROOT, AGE_PUBLIC="age1qqqq"), timeout=60)
    runs += 1
    if p.returncode != 3 or os.path.exists(os.path.join(tmp, "--quiet")):
        findings.append(f"`state backup --quiet` exits {p.returncode} and {'wrote' if os.path.exists(os.path.join(tmp, '--quiet')) else 'did not write'} a file named «--quiet»: a flag is taken for the output")

for x in findings:
    print(x)
print(f"SCOPE: {runs} run(s): every `<cmd> <verb> --help` of the commands that exec a verb script, in an empty HOME; a flag given to state backup")
