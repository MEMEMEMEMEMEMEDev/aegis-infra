"""Check 261 — what the product stages for another repo is ignored by the platform repo.

MEASURED 2026-09-30 on alpha-arch: after `aegis app new portafolio`, every
`aegis seed apply` refused to run («the platform repo has uncommitted
changes») because of one untracked directory, .aegis-app/ — the staging
area where the app's skeleton and Jenkinsfile wait for `aegis app apply`
to push them to the APP's repo. lib/aegis/org.py had always said «that is
why .aegis-app/ is in the .gitignore», and the seed's .gitignore never had
it (a claim of absence ageing quietly: the hackathon noted it on 2026-09-26).

The check reads the staging directory's name from the code that writes it
(STAGING_DIR in lib/aegis/org.py and libexec/aegis-app) and asks git
itself, in a scratch repo carrying the seed's .gitignore, whether a file in
it is ignored — not whether a line looks right.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
findings = []
names = set()
for rel in ("lib/aegis/org.py", "libexec/aegis-app"):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        for m in re.finditer(r'^STAGING_DIR\s*=\s*os\.path\.join\([A-Z_]+,\s*"([^"]+)"\)', f.read(), re.M):
            names.add(m.group(1))
if not names:
    print("SCOPE: no STAGING_DIR found in lib/aegis/org.py or libexec/aegis-app — nothing staged to ignore")
    sys.exit(0)

if not shutil.which("git"):
    print("SCOPE: git is not on this machine — the ignore rule cannot be asked")
    sys.exit(0)
with tempfile.TemporaryDirectory() as tmp:
    shutil.copy(os.path.join(ROOT, "seed", "platform", ".gitignore"), os.path.join(tmp, ".gitignore"))
    subprocess.run(["git", "init", "-q", tmp], check=True)
    for n in sorted(names):
        probe = os.path.join(n, "portafolio", "app", "Jenkinsfile")
        os.makedirs(os.path.join(tmp, os.path.dirname(probe)), exist_ok=True)
        open(os.path.join(tmp, probe), "w").close()
        p = subprocess.run(["git", "-C", tmp, "check-ignore", "-q", probe])
        if p.returncode != 0:
            findings.append(f"{n}/ (STAGING_DIR) is not ignored by the seed's .gitignore: every `aegis seed apply` "
                            f"after an `aegis app new` refuses to run, and a `git add -A` would commit another repo's files")
    st = subprocess.run(["git", "-C", tmp, "status", "--porcelain"], capture_output=True, text=True).stdout
    if any(l[3:].startswith(tuple(names)) for l in st.splitlines()):
        findings.append("git status still shows the staging area as untracked")

print(f"SCOPE: STAGING_DIR ({', '.join(sorted(names))}) read from the code that writes it; git check-ignore asked with the seed's .gitignore")
for x in findings:
    print(x)
