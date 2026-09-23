"""Check 234 — the dirty-cloud pre-check sweeps Access too, and keeps its own.

2026-09-23, second cloud VM: phase 25 swept the dead instance's tunnel and
CNAMEs and then died on five 409 «application_already_exists» — the Access
applications, policies and service token of the previous instance were
still in the account. The sweep has to see them, delete them in the order
Cloudflare accepts (apps before the policies they use), spare what THIS
instance's state owns, and be gated.

Driven: the listing is lifted out of the phase and answered with fake API
shapes; the module's names are cross-read so the phase cannot drift.
"""
import os
import re
import subprocess
import sys

ROOT = sys.argv[1]
PH = os.path.join(ROOT, "init", "phases", "25-edge-tofu.sh")
MOD = os.path.join(ROOT, "seed", "platform", "tofu", "modules", "cloudflare-access", "main.tf")
findings = []
driven = 0

raw = open(PH, encoding="utf-8").read()
src = "\n".join(l for l in raw.splitlines() if not re.match(r"^\s*#", l))

def fn(name):
    m = re.search(r"^\s{4}" + re.escape(name) + r"\(\) \{.*?^\s{4}\}", src, re.M | re.S)
    return m.group(0) if m else None

lst, left = fn("_access_list"), fn("_access_leftovers")
if not (lst and left):
    print("phase 25 does not list the account's Access resources before the apply: a previous "
          "instance's applications answer 409 in the middle of it")
    sys.exit(0)

# the three kinds, listed in the order Cloudflare deletes them
order = [m.group(1) for m in re.finditer(r"_access_list (apps|policies|service_tokens)\b", left)]
if order != ["apps", "policies", "service_tokens"]:
    findings.append(f"the leftovers are listed as {order}: apps must come first (a policy in use "
                    "refuses to be deleted) and the service token last")

# the DELETE, in the pre-check and before the apply
_del = re.search(r'_cf_access -X DELETE "\$CFB/accounts/\$CF_ACCOUNT_ID/access/\$kind/\$id"', src)
if not _del:
    findings.append("nothing deletes the Access leftovers: they are only listed, and the apply still "
                    "hits the 409")
_ap = re.search(r'"\$TOFU"[^\n]*\bapply\b', src)
if _del and _ap and _ap.start() < _del.start():
    findings.append("the Access sweep runs after the apply: the 409 has already happened")

# the gate, on both edges
if not re.search(r'gate\s+"access-sin-restos"\s+_access_swept', src):
    findings.append("the sweep is not gated: a leftover that survives the delete is not a failure")
if not re.search(r'gate_no_subject\s+"access-sin-restos"', src):
    findings.append("the gate is never declared subjectless: the local edge (and a token that cannot "
                    "list) would leave it unmeasured in silence")

# the names the phase looks for are the module's names, not a memory of them
mod = open(MOD, encoding="utf-8").read()
def names_of(rtype):
    out = []
    for m in re.finditer(r'resource "' + rtype + r'" "[^"]+" \{(.*?)^\}', mod, re.M | re.S):
        n = re.search(r'^\s*name\s*=\s*"([^"]+)"', m.group(1), re.M)
        if n:
            out.append(n.group(1))
    return out
mod_policies = set(names_of("cloudflare_zero_trust_access_policy"))
mod_st = set(names_of("cloudflare_zero_trust_access_service_token"))
ph_pol = re.search(r'^\s*ACCESS_POLICY_NAMES="([^"]*)"', src, re.M)
ph_st = re.search(r'^\s*ACCESS_ST_NAME="([^"]*)"', src, re.M)
if not ph_pol or set(ph_pol.group(1).split()) != mod_policies:
    findings.append(f"the policy names phase 25 sweeps ({ph_pol.group(1) if ph_pol else 'none'}) are not "
                    f"the module's ({' '.join(sorted(mod_policies))}): a renamed policy is left behind")
if not ph_st or {ph_st.group(1)} != mod_st:
    findings.append(f"the service token name phase 25 sweeps ({ph_st.group(1) if ph_st else 'none'}) is "
                    f"not the module's ({' '.join(sorted(mod_st))})")

# driven: the listing against fake shapes
APPS = ('{"success":true,"result":[{"id":"app-old","domain":"argocd.example.cl","name":"aegis · ArgoCD"},'
        '{"id":"app-hook","domain":"jenkins.example.cl/github-webhook/","name":"aegis · jenkins webhook"},'
        '{"id":"app-other","domain":"argocd.otherproject.cl","name":"someone else"}]}')
POLS = ('{"success":true,"result":[{"id":"pol-old","name":"aegis-operador"},{"id":"pol-mine","name":"aegis-operador"},'
        '{"id":"pol-foreign","name":"their-policy"}]}')
STS = '{"success":true,"result":[{"id":"st-old","name":"aegis-automatizacion"},{"id":"st-mine","name":"aegis-automatizacion"}]}'
DENIED = '{"success":false,"errors":[{"code":10000,"message":"Authentication error"}]}'
body = re.sub(r"^\s{4}", "", lst + "\n" + left, flags=re.M)
def drive(apps, pols, sts, known):
    script = (
        'log_warn() { echo "$*" >&2; }\n'
        'CF_ACCOUNT_ID=acc; CFB=https://api.cloudflare.com/client/v4; ROOT_DOMAIN=example.cl\n'
        f'ACCESS_POLICY_NAMES="{" ".join(sorted(mod_policies))}"; ACCESS_ST_NAME="{next(iter(mod_st), "")}"\n'
        '_cf_access() { case "$1" in *apps*) printf %s "$APPS";; *policies*) printf %s "$POLS";; *service_tokens*) printf %s "$STS";; esac; }\n'
        f"{body}\n"
        f'_access_state_ids() {{ printf "%s\\n" {known}; }}\n'
        "_access_leftovers\n")
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env={**os.environ, "APPS": apps, "POLS": pols, "STS": sts})
    return r.returncode, r.stdout.split("\n") if r.stdout.strip() else []

rc, lines = drive(APPS, POLS, STS, "pol-mine st-mine")
driven += 1
got = [l.split()[:2] for l in lines if l]
want = [["apps", "app-old"], ["apps", "app-hook"], ["policies", "pol-old"], ["service_tokens", "st-old"]]
if rc != 0 or got != want:
    findings.append(f"with a dead instance's app, webhook app, policy and token next to this instance's "
                    f"own policy and token, the sweep listed {got} (rc {rc}), expected {want}: "
                    "either a leftover survives, our own resource is eaten, a foreign one is taken, "
                    "or the order is wrong")

rc, lines = drive(APPS.replace("app-old", "x").replace("app-hook", "y"),
                  POLS, STS, "pol-old pol-mine st-old st-mine")
driven += 1
got = [l.split()[1] for l in lines if l]
if rc != 0 or got != ["x", "y"]:
    findings.append(f"when the state owns every policy and token, only the foreign-domain-free apps "
                    f"should remain; got {got}")

rc, lines = drive(DENIED, POLS, STS, "")
driven += 1
if rc != 2:
    findings.append(f"a token that cannot list Access answered rc {rc}, expected 2 (NOT measured): "
                    "an empty answer would be read as a clean account")

for f in findings:
    print(f)
print(f"SCOPE: the sweep's order, delete, gate on both edges, names cross-read from the module, "
      f"and the listing driven {driven} times")
