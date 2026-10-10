"""Check 280 — the node defends its disk, and warns before it has to.

plan/19 B-6 (2026-09-24): the node met a filling disk with no eviction and
no alert. The cause, found on 2026-10-10: `eviction-hard` is one map, and
a kubelet given any of it does not merge in its defaults for the signals
left out — the drop-in aegis has written since 2026-09-10 said only
`memory.available`, which switched the kubelet's disk thresholds OFF.

Driven: the drop-in text is generated (lib/aegis/host.py) for a sample
reservation and its eviction-hard parsed: memory AND nodefs/imagefs.
Read, comment-stripped: phase 20 asks the RUNNING kubelet (configz) for
the disk signals, over every node and never items[0]; the host metrics
publish the disk's size and free bytes; an alert warns before the
kubelet's first threshold, and its absence sibling covers the new series.
"""
import os
import re
import sys

import yaml

ROOT = os.path.abspath(sys.argv[1])
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []
scope = []


def code(rel):
    try:
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    except OSError:
        findings.append(f"{rel} is missing")
        return ""
    return "\n".join(l for l in text.splitlines() if not re.match(r"^\s*#", l))


# ── driven: the drop-in the host bootstrap writes ───────────────────────
try:
    from aegis import host as hostlib
    r = {"floor": {"step": "x", "ram_bytes": 1, "source": "sample"}, "ram_total_bytes": 10,
         "system_reserved_bytes": 3, "eviction_bytes": 1, "allocatable_bytes": 6,
         "system_reserved": "3Gi", "eviction": "500Mi"}
    text = hostlib.kubelet_dropin_text(r)
    args = (yaml.safe_load(text) or {}).get("kubelet-arg") or []
    hard = [a for a in args if a.startswith("eviction-hard=")]
    if len(hard) != 1:
        findings.append(f"the drop-in carries {len(hard)} eviction-hard arguments, not one: the kubelet "
                        "keeps the last and drops the rest")
    else:
        sig = dict(x.split("<", 1) for x in hard[0].split("=", 1)[1].split(",") if "<" in x)
        if sig.get("memory.available") != "500Mi":
            findings.append("the drop-in's eviction-hard lost the derived memory margin")
        for s in ("nodefs.available", "nodefs.inodesFree", "imagefs.available", "imagefs.inodesFree"):
            if s not in sig:
                findings.append(f"the drop-in's eviction-hard has no {s}: a kubelet given part of the map "
                                "drops its own defaults, and the disk meets no eviction")
    scope.append("the kubelet drop-in generated and parsed")
except Exception as e:   # the generator itself is under test: say how it broke
    findings.append(f"the kubelet drop-in could not be generated: {e!r}")

# ── phase 20: the running kubelet is asked ──────────────────────────────
p20 = code("init/phases/20-k3s.sh")
m = re.search(r"_kubelet_evicts_on_disk\(\)\s*\{(.*?)\n\}", p20, re.S)
if not m:
    findings.append("phase 20 does not ask the running kubelet whether it evicts on disk: a drop-in that "
                    "says nodefs and a kubelet that did not read it look the same")
else:
    body = m.group(1)
    if "/proxy/configz" not in body:
        findings.append("phase 20's disk-eviction gate does not read configz: it reads what we wrote, not "
                        "what the kubelet runs")
    if "items[0]" in body:
        findings.append("phase 20's disk-eviction gate reads items[0]: one node of many (check 72)")
    for s in ("nodefs.available", "imagefs.available"):
        if s not in body:
            findings.append(f"phase 20's disk-eviction gate does not ask for {s}")
if not re.search(r'gate "kubelet-desaloja-por-disco"[^\n]*_kubelet_evicts_on_disk', p20):
    findings.append("phase 20 defines the disk-eviction probe but no gate runs it")
scope.append("phase 20 read")

# ── the warning ─────────────────────────────────────────────────────────
hostcli = code("libexec/aegis-host")
for mname in ("aegis_host_disk_free_bytes", "aegis_host_disk_size_bytes"):
    if f'"{mname}"' not in hostcli:
        findings.append(f"the host metrics do not publish {mname}: nothing can warn about the disk")
rules_raw = yaml.safe_load(open(os.path.join(ROOT, "seed", "platform", "k8s", "base", "observability",
                                             "rules", "vmalert-rules.yaml"), encoding="utf-8"))
alerts = {}
for doc in (rules_raw.get("data") or {}).values():
    for g in (yaml.safe_load(doc) or {}).get("groups") or []:
        for rule in g.get("rules") or []:
            if rule.get("alert"):
                alerts[rule["alert"]] = rule
disk = [a for a in alerts.values() if "aegis_host_disk_free_bytes" in a.get("expr", "")
        and "aegis_host_disk_size_bytes" in a.get("expr", "")]
if not disk:
    findings.append("no alert reads the disk's free share: the node fills up in silence")
else:
    t = re.search(r"<\s*(0?\.\d+)", disk[0]["expr"])
    if not t or not 0.15 < float(t.group(1)) <= 0.30:
        findings.append("the disk alert does not fire before the kubelet's first threshold (imagefs at 15% "
                        "free): it would arrive after the eviction it is meant to precede")
absent = (alerts.get("MedicionDelAnfitrionAusente") or {}).get("expr", "")
for mname in ("aegis_host_disk_free_bytes", "aegis_host_disk_size_bytes"):
    if f"absent(last_over_time({mname}" not in absent:
        findings.append(f"MedicionDelAnfitrionAusente does not cover {mname}: the disk alert goes mute, "
                        "not green, when the series stops")
scope.append("host metrics and alert rules read")

for x in findings:
    print(x)
print(f"SCOPE: {'; '.join(scope)}")
