"""Check 233 — the GPU device plugin lands only on a node that says it has
a card, and phase 20 is the one that says it.

2026-09-23, the first cloud instance (AI=no): `k8s/base/gpu` is part of the
core, so its DaemonSet reached a node with no NVIDIA runtime and sat
ContainerCreating for hours («unable to get OCI runtime for sandbox»),
the kubelet retrying every two seconds and the ArgoCD app `gpu` stuck in
Progressing. A DaemonSet with a nodeSelector nobody carries wants zero
pods and is healthy; the label is the switch, and the phase that knows
AI is the one that flips it, in both directions.
"""
import os
import re
import sys

import yaml

ROOT = sys.argv[1]
DS = os.path.join(ROOT, "seed", "platform", "k8s", "base", "gpu", "device-plugin.yaml")
PH = os.path.join(ROOT, "init", "phases", "20-k3s.sh")
findings = []

LABEL = "aegis.dev/gpu"
docs = [d for d in yaml.safe_load_all(open(DS, encoding="utf-8")) if d]
ds = [d for d in docs if d.get("kind") == "DaemonSet"]
if not ds:
    findings.append("k8s/base/gpu/device-plugin.yaml carries no DaemonSet")
else:
    sel = (ds[0].get("spec", {}).get("template", {}).get("spec", {}).get("nodeSelector") or {})
    if sel.get(LABEL) != "true":
        findings.append(f"the device plugin's DaemonSet has no nodeSelector {LABEL}=true: it lands on "
                        "every node, card or not, and on a node without the NVIDIA runtime its pod "
                        "never starts")

ph = "\n".join(l for l in open(PH, encoding="utf-8").read().splitlines()
               if not re.match(r"^\s*#", l))
m = re.search(r'if \[\[ "\$AI" == "gpu" \]\]; then(.*?)\nelse(.*?)\nfi', ph, re.S)
blocks = [(a, b) for a, b in re.findall(r'if \[\[ "\$AI" == "gpu" \]\]; then(.*?)\nelse(.*?)\nfi', ph, re.S)]
gpu_side = "\n".join(a for a, _ in blocks)
other_side = "\n".join(b for _, b in blocks)
if not re.search(rf"kubectl label node --all --overwrite {re.escape(LABEL)}=true", gpu_side):
    findings.append(f"phase 20 does not put {LABEL}=true on the node under AI=gpu: the plugin would "
                    "want zero pods on the one instance that has a card")
if not re.search(rf'gate\s+"gpu-node-labelled"', gpu_side):
    findings.append("phase 20 labels the node under AI=gpu and never measures that a node carries "
                    "the label")
if not re.search(rf"kubectl label node --all {re.escape(LABEL)}-", other_side):
    findings.append(f"phase 20 does not take {LABEL} off under AI=no/cpu: an instance that turns "
                    "the GPU off keeps a plugin that can never start")
if not re.search(r'gate_no_subject\s+"gpu-node-labelled"', other_side):
    findings.append("under AI=no/cpu the gate gpu-node-labelled disappears instead of being "
                    "declared without a subject")

for f in findings:
    print(f)
print(f"SCOPE: the DaemonSet's nodeSelector parsed, and both branches of phase 20 read for the label")
