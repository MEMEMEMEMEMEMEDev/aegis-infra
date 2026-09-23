"""Check 231 — Access being off is discovered before anything is created.

2026-09-22, the first cloud instance: a brand new Cloudflare account has
Zero Trust dormant, so every Access call answers 403
«access.api.error.not_enabled». Phase 25 found out in the middle of
`tofu apply`, with the tunnel module already run and the policies half
created, and nothing in the product or the docs had said a word.

Driven: the gate's probe is lifted out of the phase and answered with
the three shapes the API produces.
"""
import os
import re
import subprocess
import sys

ROOT = sys.argv[1]
PH = os.path.join(ROOT, "init", "phases", "25-edge-tofu.sh")
JOURNEY = os.path.join(ROOT, "docs", "journeys", "your-machine.md")
findings = []
driven = 0

raw = open(PH, encoding="utf-8").read()
# comments are prose: the phase's header names `tofu apply` while
# explaining itself, and a position computed over it accuses the gate of
# running late (the check's own first draft did exactly that)
src = "\n".join(l for l in raw.splitlines() if not re.match(r"^\s*#", l))
m = re.search(r"^\s*_access_enabled\(\) \{.*?^\s*\}", src, re.M | re.S)
if not m:
    print("phase 25 does not ask whether Access is enabled: the run finds out inside tofu apply, "
          "with resources half created")
    sys.exit(0)
probe = re.sub(r"^\s{4}", "", m.group(0), flags=re.M)

# THE GATE, not the function's name: a phase that defines the probe and
# never gates on it measures nothing, and the first draft of this check
# was satisfied by the definition alone (tooth red_1)
_g = re.search(r'gate\s+"[^"]*access[^"]*"\s+_access_enabled', src)
if not _g:
    findings.append("phase 25 defines the Access probe and never gates on it: nothing stops the "
                    "apply when Zero Trust is dormant")
i_gate = _g.start() if _g else len(src)
# the APPLY, not the variable that holds the wrapper's path
_ap = re.search(r'"\$TOFU"[^\n]*\bapply\b', src)
i_apply = _ap.start() if _ap else -1
if 0 <= i_apply < i_gate:
    findings.append("the Access gate runs after the apply: the resources are already being created "
                    "when the run learns Access is off")

body = m.group(0)
if "one.dash.cloudflare.com" not in body:
    findings.append("the refusal does not name the page that enables Zero Trust")

# the journey a new operator reads has to say it too
try:
    j = open(JOURNEY, encoding="utf-8").read().lower()
except OSError:
    j = ""
if "zero trust" not in j:
    findings.append("docs/journeys/your-machine.md never mentions Zero Trust: the operator who "
                    "prepares a Cloudflare account has no way to know it must be switched on")

SHAPES = [
    ("a token that cannot read Zero Trust (auth error)",
     '{"success":false,"errors":[{"code":10000,"message":"Authentication error"}]}', 0),
    ("Access dormant (403 not_enabled)",
     '{"success":false,"errors":[{"code":9999,"message":"access.api.error.not_enabled: Access is not enabled."}]}', 1),
    ("Access enabled", '{"success":true,"result":[{"id":"x","name":"team"}]}', 0),
    ("Cloudflare unreachable (empty answer)", "", 0),
]
for name, payload, want in SHAPES:
    script = (
        'log_error() { echo "$*" >&2; }\n'
        'log_warn() { echo "$*" >&2; }\n'
        f'CF_ACCOUNT_ID=acc; CFB=https://api.cloudflare.com/client/v4\n'
        f'_cf() {{ printf %s {payload!r}; }}\n'
        f'_cf_access() {{ printf %s {payload!r}; }}\n'
        f"{probe}\n_access_enabled\n")
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    driven += 1
    if r.returncode != want:
        findings.append(f"with {name} the probe answered rc {r.returncode}, expected {want}"
                        + (": the phase walks into the apply" if want == 1 else
                           ": a run that could go ahead is stopped"))
    if name.startswith("a token that cannot") and "NOT measured" not in r.stderr:
        findings.append("a token that cannot read Zero Trust is not an account with it off: the "
                        "probe must say NOT measured, not refuse")
    if want == 1 and "one.dash" not in r.stderr:
        findings.append("the refusal does not tell the operator where to enable Access")

for f in findings:
    print(f)
print(f"SCOPE: the gate before the apply, the journey's wording, and the probe driven {driven} times")
