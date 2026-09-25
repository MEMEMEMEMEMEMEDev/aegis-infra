"""Check 248 — `gpu: true` on a service is the one door to the card, and it opens for that service only.

2026-09-25: the hackathon's organization needs the home GPU for ONE worker,
the same day tenants-without-gpu closed the card to every organization
(check 247). The grant is DRIVEN here: two contracts are rendered through
the real generator against a throwaway aegis.conf, and the ClusterPolicy
is read for the exception it makes.
"""
import os
import re
import sys
import tempfile

import yaml

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []
POL = os.path.join(ROOT, "seed", "platform", "k8s", "base", "kyverno-policies",
                   "clusterpolicy-tenants-without-gpu.yaml")
PLANS = os.path.join(ROOT, "seed", "platform", "plans.yaml")

CONTRACT = """version: 1
organizacion: tarjeta
cuota: grande
repo: acme/tarjeta
servicios:
  - {nombre: hub, tipo: http, puerto: 8080}
  - {nombre: motor, tipo: worker, gpu: true}
"""


def docs(text):
    return [d for d in yaml.safe_load_all(text) if d]


with tempfile.TemporaryDirectory() as tmp:
    conf = os.path.join(tmp, "aegis.conf")
    os.environ["AEGIS_CONF"] = conf
    try:
        from aegis import org
    except Exception as e:  # noqa: BLE001
        print(f"the generator does not import: {e}")
        sys.exit(0)
    plans = yaml.safe_load(open(PLANS, encoding="utf-8"))

    def validate(raw, lane="gpu"):
        open(conf, "w").write(f'EDGE="local"\nAI="{lane}"\n')
        return org.validate(yaml.safe_load(raw), plans)

    def refused(raw, lane="gpu"):
        try:
            validate(raw, lane)
            return False
        except org.Invalid:
            return True

    grant = getattr(org, "GPU_GRANT", None)
    if not grant:
        print("the generator names no GPU grant label: nothing ties the contract to the policy's exception")
        sys.exit(0)

    # ── rendered, with and without ────────────────────────────────────
    try:
        c = validate(CONTRACT)
        files, _ = org.render(c, plans, CONTRACT)
    except Exception as e:  # noqa: BLE001
        findings.append(f"a contract with gpu: true does not render: {str(e).splitlines()[0]}")
        files = {}
    if files:
        b = docs(files["bundle.yaml"])
        ns = next((d for d in b if d.get("kind") == "Namespace"), {})
        q = next((d for d in b if d.get("kind") == "ResourceQuota"), {})
        pol = next((d for d in b if d.get("kind") == "Policy"), {})
        if (ns.get("metadata", {}).get("labels") or {}).get(grant) != "true":
            findings.append(f"the Namespace of a gpu organization does not carry {grant}: the policy refuses the card it granted")
        if str((q.get("spec", {}).get("hard") or {}).get("requests.nvidia.com/gpu")) != "1":
            findings.append("the quota of a gpu organization does not cap nvidia.com/gpu at one card")
        rules = (pol.get("spec") or {}).get("rules") or []
        sel = lambda r: (((r.get("match") or {}).get("any") or [{}])[0].get("resources") or {}).get("selector", {}).get("matchLabels", {}).get("app")
        rc = [r for r in rules if (((r.get("mutate") or {}).get("patchStrategicMerge") or {}).get("spec") or {}).get("runtimeClassName") == "nvidia"]
        if not rc or any(sel(r) != "tarjeta-motor" for r in rc):
            findings.append("the sizes Policy does not write runtimeClassName nvidia into the gpu service's pods (and only those)")
        card = []
        for r in rules:
            for fe in ((r.get("mutate") or {}).get("foreach") or []):
                for ct in (((fe.get("patchStrategicMerge") or {}).get("spec") or {}).get("containers") or []):
                    res = ct.get("resources") or {}
                    if str((res.get("limits") or {}).get("nvidia.com/gpu")) == "1" and \
                            str((res.get("requests") or {}).get("nvidia.com/gpu")) == "1":
                        card.append(sel(r))
        if card != ["tarjeta-motor"]:
            findings.append(f"the card is written into the pods of {card or 'no service'}, not exactly the gpu one")
    plain = CONTRACT.replace(", gpu: true", "")
    f2, _ = org.render(validate(plain), plans, plain)
    b2 = f2["bundle.yaml"]
    if grant in b2 or "nvidia" in "\n".join(l for l in b2.splitlines() if not l.lstrip().startswith("#")):
        findings.append("an organization WITHOUT gpu gets the grant label, the quota or the runtime class")

    # ── refused ──────────────────────────────────────────────────────
    for raw, lane, why in [
        (CONTRACT.replace("gpu: true", "gpu: 1"), "gpu", "a gpu value other than true"),
        (CONTRACT.replace("{nombre: hub, tipo: http, puerto: 8080}", "{nombre: hub, tipo: http, puerto: 8080, gpu: true}"),
         "gpu", "two services with gpu"),
        (CONTRACT + "  - {nombre: bus, tipo: redis, gpu: true}\n", "gpu", "gpu on a provided type"),
        (CONTRACT, "cpu", "gpu on an instance whose AI lane is cpu"),
    ]:
        if not refused(raw, lane):
            findings.append(f"the contract validates with {why}")

# ── the policy's exception is exactly the grant ──────────────────────
pol = yaml.safe_load(open(POL, encoding="utf-8")) or {}
rules = {r.get("name"): r for r in (pol.get("spec") or {}).get("rules") or []}
for name in ("no-runtime-class", "no-gpu-resource"):
    ex = ((rules.get(name) or {}).get("exclude") or {}).get("any") or []
    labels = [((e.get("resources") or {}).get("namespaceSelector") or {}).get("matchLabels") for e in ex]
    if labels != [{grant: "true"}]:
        findings.append(f"{name} does not step aside for exactly the grant label ({grant}), and for nothing else")
ask = rules.get("granted-runtime-asks-for-the-card") or {}
spec = ((ask.get("validate") or {}).get("pattern") or {}).get("spec") or {}
cts = spec.get("containers") or [{}]
if spec.get("(runtimeClassName)") != "nvidia" or \
        str(((cts[0].get("resources") or {}).get("limits") or {}).get("nvidia.com/gpu")) != "?*":
    findings.append("in a granted namespace the nvidia runtime is not tied to asking for nvidia.com/gpu: "
                    "a container sees the card outside the quota")
only = rules.get("granted-runtime-is-nvidia") or {}
if (((only.get("validate") or {}).get("pattern") or {}).get("spec") or {}).get("=(runtimeClassName)") != "nvidia":
    findings.append("in a granted namespace any runtime class is accepted, not only nvidia")
for name in ("granted-runtime-is-nvidia", "granted-runtime-asks-for-the-card"):
    m = (((rules.get(name) or {}).get("match") or {}).get("any") or [{}])[0].get("resources") or {}
    if (m.get("namespaceSelector") or {}).get("matchLabels") != {grant: "true"}:
        findings.append(f"{name} does not select the grant label {grant}")
    if ((rules.get(name) or {}).get("validate") or {}).get("failureAction") != "Enforce":
        findings.append(f"{name} does not Enforce")

for f in findings:
    print(f)
print(f"SCOPE: two contracts rendered (grant label {grant}), four refused, {len(rules)} policy rules read")
