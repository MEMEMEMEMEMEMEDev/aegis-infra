"""Check 247 — an organization does not reach the GPU unless the platform hands it one.

2026-09-25, home instance, org-canary (restricted PSS, signed image): a pod
asking for `nvidia.com/gpu: 1` was admitted (no quota named the resource),
and a pod asking for NOTHING, with `runtimeClassName: nvidia` and
`NVIDIA_VISIBLE_DEVICES=all`, listed /dev/nvidia0, /dev/nvidiactl and
/dev/nvidia-uvm. The fix is the ClusterPolicy `tenants-without-gpu`, listed
from the seed; phases 35 and 80 now touch only the signature entry of that
kustomization, through `signature_policy_entry`, which is DRIVEN here over
four lists.
"""
import fnmatch
import os
import re
import subprocess
import sys
import tempfile

import yaml

ROOT = sys.argv[1]
KP = os.path.join(ROOT, "seed", "platform", "k8s", "base", "kyverno-policies")
POL = os.path.join(KP, "clusterpolicy-tenants-without-gpu.yaml")
KUS = os.path.join(KP, "kustomization.yaml")
COMMON = os.path.join(ROOT, "lib", "common.sh")
PH35 = os.path.join(ROOT, "init", "phases", "35-gitops.sh")
PH80 = os.path.join(ROOT, "init", "phases", "80-supply-chain.sh")
SIG = "clusterpolicy-require-aegis-signature.yaml"
GPU = "clusterpolicy-tenants-without-gpu.yaml"
findings = []


def code(path):
    return "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                     if not re.match(r"^\s*#", l))


def strip_anchor(k):
    m = re.match(r"^[=X+^<]?\((.*)\)$", k)
    return m.group(1) if m else k


def child(d, name):
    """The value under `name` whatever anchor wraps it, and the raw key."""
    for k, v in (d or {}).items():
        if strip_anchor(k) == name:
            return k, v
    return None, None


# ── the policy ────────────────────────────────────────────────────────
if not os.path.isfile(POL):
    print("there is no tenants-without-gpu policy: any organization's repo can take the GPU")
    sys.exit(0)
pol = yaml.safe_load(open(POL, encoding="utf-8")) or {}
if pol.get("kind") != "ClusterPolicy":
    findings.append("tenants-without-gpu is not a ClusterPolicy")
spec = pol.get("spec") or {}
if (spec.get("webhookConfiguration") or {}).get("failurePolicy") != "Fail":
    findings.append("the policy's webhook does not fail closed: with Kyverno down a pod asking for the GPU is admitted")

rules = spec.get("rules") or []
have = {"runtime": False, "gpu": set(), "env": set()}
for r in rules:
    name = r.get("name", "?")
    v = r.get("validate") or {}
    if v.get("failureAction") != "Enforce":
        findings.append(f"rule {name} does not Enforce: it reports the GPU taken and lets it be taken")
    if v.get("allowExistingViolations") is not False:
        findings.append(f"rule {name} does not declare allowExistingViolations: false: a pod already holding "
                        "the card is updated in place, and Kyverno's default reads as drift in ArgoCD")
    scopes = [x.get("resources") or {} for x in ((r.get("match") or {}).get("any") or [])]
    ns = [g for s in scopes for g in (s.get("namespaces") or [])]
    sel = [s.get("namespaceSelector") for s in scopes if s.get("namespaceSelector")]
    if not any("Pod" in (s.get("kinds") or []) for s in scopes):
        findings.append(f"rule {name} does not match Pods")
    # The refusing rules (no-*) cover EVERY organization; the rules for a
    # granted namespace (check 248) narrow to the grant label on purpose.
    granted = [x for x in sel if (x.get("matchLabels") or {}).get("aegis.dev/gpu-otorgada") == "true"]
    if not any(fnmatch.fnmatch("org-conf", g) for g in ns) or (sel and not name.startswith("granted-")):
        findings.append(f"rule {name} does not cover every organization's namespace (org-*)")
    if name.startswith("granted-") and not granted:
        findings.append(f"rule {name} is for granted namespaces and does not select the grant label")
    if any(fnmatch.fnmatch("ai-system", g) for g in ns) or any("aegis-tenants" in str(x) for x in sel):
        findings.append(f"rule {name} also covers ai-system: the platform's own GPU lane would be refused")
    if name == "no-nvidia-env" and r.get("exclude"):
        findings.append("the NVIDIA_* env rule has an exception: with the nvidia runtime granted, "
                        "the variable would hand over the card outside the quota")
    pspec = ((v.get("pattern") or {}).get("spec")) or {}
    k, _ = child(pspec, "runtimeClassName")
    if k and k.startswith("X("):
        have["runtime"] = True
    for field in ("containers", "initContainers", "ephemeralContainers"):
        _, lst = child(pspec, field)
        for el in lst if isinstance(lst, list) else []:
            _, res = child(el, "resources")
            if res is not None:
                ok = []
                for side in ("limits", "requests"):
                    _, sd = child(res, side)
                    gk, _ = child(sd, "nvidia.com/gpu")
                    ok.append(bool(gk and gk.startswith("X(")))
                if all(ok):
                    have["gpu"].add(field)
            _, env = child(el, "env")
            for e in env if isinstance(env, list) else []:
                n = str((e or {}).get("name", ""))
                if n.startswith("!") and fnmatch.fnmatch("NVIDIA_VISIBLE_DEVICES", n[1:]) \
                        and fnmatch.fnmatch("NVIDIA_DRIVER_CAPABILITIES", n[1:]):
                    have["env"].add(field)
if not have["runtime"]:
    findings.append("no rule refuses runtimeClassName: `nvidia` + NVIDIA_VISIBLE_DEVICES hands over the whole card")
for f in ("containers", "initContainers"):
    if f not in have["gpu"]:
        findings.append(f"no rule refuses nvidia.com/gpu in the limits AND requests of {f}")
for f in ("containers", "initContainers", "ephemeralContainers"):
    if f not in have["env"]:
        findings.append(f"no rule refuses NVIDIA_* variables in {f}")

# ── listed from the seed ──────────────────────────────────────────────
res = (yaml.safe_load(open(KUS, encoding="utf-8")) or {}).get("resources") or []
if GPU not in res:
    findings.append("the kyverno-policies kustomization does not list tenants-without-gpu: the policy never reaches the cluster")
if SIG in res:
    findings.append("the seed lists the signature policy: it would go live before phase 80 (check 039)")

# ── the helper, driven ────────────────────────────────────────────────
m = re.search(r"^signature_policy_entry\(\) \{.*?^\}", open(COMMON, encoding="utf-8").read(), re.M | re.S)
driven = 0
if not m:
    findings.append("lib/common.sh has no signature_policy_entry: the phases swap the whole list")
else:
    cases = [([GPU], "on", [SIG, GPU]), ([SIG, GPU], "off", [GPU]),
             ([], "on", [SIG]), ([SIG], "off", []), ([SIG, GPU], "on", [SIG, GPU])]
    with tempfile.TemporaryDirectory() as tmp:
        for start, op, want in cases:
            k = os.path.join(tmp, "kustomization.yaml")
            body = ("resources:\n" + "".join(f"  - {x}\n" for x in start)) if start else "resources: []\n"
            open(k, "w").write("apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n# a comment\n" + body)
            rc = subprocess.run(["bash", "-c", m.group(0) + '\nsignature_policy_entry "$1" "$2"', "_", op, k],
                                capture_output=True, text=True).returncode
            try:
                got = (yaml.safe_load(open(k)) or {}).get("resources") or []
            except yaml.YAMLError:
                got = "not YAML"
            driven += 1
            if rc != 0 or got != want:
                findings.append(f"signature_policy_entry {op} over {start or '[]'} leaves {got} (rc {rc}), not {want}")

# ── the phases go through it ──────────────────────────────────────────
c80, c35 = code(PH80), code(PH35)
if not re.search(r'^\s*run_cmd signature_policy_entry on "\$KPK"', c80, re.M):
    findings.append("phase 80 does not turn the signature on through signature_policy_entry")
if not re.search(r'^\s*run_cmd signature_policy_entry off "\$KPK35"', c35, re.M):
    findings.append("phase 35 does not turn the signature off through signature_policy_entry")
for ph, c in (("80", c80), ("35", c35)):
    if re.search(r'"resources: \[\]"', c):
        findings.append(f"phase {ph} still swaps the literal `resources: []`: with two entries it breaks the list")
gate = re.search(r'gate "politica-apagada-hasta-80".*\n.*', c35)
if not gate or SIG not in gate.group(0) or "'clusterpolicy' in x" in gate.group(0):
    findings.append("phase 35's gate does not ask about the SIGNATURE entry: tenants-without-gpu would read as the policy left on")

for f in findings:
    print(f)
print(f"SCOPE: {len(rules)} rules over org-*, helper driven over {driven} lists, phases 35 and 80")
