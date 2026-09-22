"""Check 229 — the owner's deploy-key policy is asked before anything exists.

2026-09-22, the first cloud instance: phase 15 died with «Deploy keys are
disabled for this repository» after creating two repositories and minting
two Cloudflare tokens. A GitHub organization forbids deploy keys by
default (`deploy_keys_enabled_for_repositories = false`), and ArgoCD and
Jenkins read the repos with those keys.

Driven: the check is run against a fake `gh` that answers as a personal
account, as an organization that allows them, as one that forbids them,
and as an API that cannot be asked.
"""
import os
import re
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
CHECKS = os.path.join(ROOT, "lib", "checks.sh")
P00 = os.path.join(ROOT, "init", "phases", "00-preflight.sh")
findings = []
driven = 0


def nc(path):
    with open(path, encoding="utf-8") as f:
        return "\n".join(l for l in f.read().splitlines() if not re.match(r"^\s*#", l))


ph = nc(P00)
# the gate exists, and BEFORE the phase that would pay for its absence:
# phase 00 is where the run can still stop having touched nothing
if "check_gh_org_allows_deploy_keys" not in ph:
    findings.append("phase 00 never asks whether the owner allows deploy keys: the run finds out "
                    "in phase 15, with the repositories created and the Cloudflare tokens minted")
elif not re.search(r'gate\s+"[^"]*deploy-keys[^"]*"\s+check_gh_org_allows_deploy_keys\s+"\$GH_OWNER"', ph):
    findings.append("phase 00 mentions the deploy-key policy but not as a gate on $GH_OWNER")

i_gate = ph.find("check_gh_org_allows_deploy_keys")
i_seed = ph.find("seed_platform_dir")
if 0 <= i_gate and 0 <= i_seed and i_gate < i_seed:
    findings.append("the deploy-key gate runs before the config exists: $GH_OWNER is not known yet")

# ── driven: a fake gh, four answers ─────────────────────────────────
CASES = [
    ("a personal account", "User", None, 0),
    ("an organization that allows deploy keys", "Organization", "true", 0),
    ("an organization that forbids them", "Organization", "false", 1),
    ("an API that cannot be asked about the policy", "Organization", "", 0),
]
for name, kind, policy, want in CASES:
    with tempfile.TemporaryDirectory() as td:
        gh = os.path.join(td, "gh")
        with open(gh, "w") as f:
            f.write("#!/bin/sh\n"
                    'case "$*" in\n'
                    f'  *users/*) echo "{kind}" ;;\n'
                    "  *orgs/*) " + (f'echo "{policy}"' if policy else "exit 1") + " ;;\n"
                    "  *) exit 1 ;;\n"
                    "esac\n")
        os.chmod(gh, stat.S_IRWXU)
        r = subprocess.run(
            ["bash", "-c",
             # the log functions live in common.sh: a check sourced without
             # them answers 127 and says nothing, which is not what the
             # phase would see
             f"export AEGIS_ROOT='{ROOT}'; source '{ROOT}/lib/paths.sh' 2>/dev/null; "
             f"source '{ROOT}/lib/common.sh' 2>/dev/null; source '{CHECKS}' 2>/dev/null; "
             "check_gh_org_allows_deploy_keys some-owner"],
            capture_output=True, text=True,
            env={**os.environ, "PATH": td + ":" + os.environ.get("PATH", "")})
        driven += 1
        if r.returncode != want:
            findings.append(f"with {name} the check answered rc {r.returncode}, expected {want}"
                            + (": the run would walk into phase 15 and die there" if want else
                               ": a run that could have gone ahead is stopped"))
        if want == 1 and "repository-policies" not in (r.stdout + r.stderr):
            findings.append("the refusal does not name the page where the policy is changed")

for f in findings:
    print(f)
print(f"SCOPE: the gate placed in phase 00 after the config, and the check driven {driven} times "
      f"against a fake gh")
