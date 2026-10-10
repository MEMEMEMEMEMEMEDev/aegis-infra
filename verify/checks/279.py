"""Check 279 — traefik buffers bodies in a volume with a ceiling.

MEASURED 2026-09-27 on the home instance: the buffering middleware's
`temp-multibuf-*` files, orphaned by killed processes, survived container
restarts in the chart's /tmp —an `emptyDir: {}` with no ceiling, which
lives as long as the pod— and piled up to 9.7 GB on the system disk.
The chart (40.3.0) writes that volume out literally, so the values move
Go's temp dir instead: TMPDIR → a volume of our own with a sizeLimit.

Read from the values (YAML, not text): TMPDIR is set, a mount sits at
exactly that path, and the volume behind the mount is an emptyDir with a
sizeLimit. Any one of the three missing puts the buffer back on the
uncapped /tmp, or nowhere writable (the root filesystem is read-only).
"""
import os
import re
import sys

import yaml

ROOT = os.path.abspath(sys.argv[1])
VALUES = os.path.join(ROOT, "seed", "platform", "k8s", "base", "ingress", "traefik", "values.yaml")
findings = []
v = yaml.safe_load(open(VALUES, encoding="utf-8")) or {}

tmpdir = next((e.get("value") for e in (v.get("env") or []) if e.get("name") == "TMPDIR"), None)
if not tmpdir:
    findings.append("traefik has no TMPDIR: its buffer goes to the chart's /tmp, an emptyDir with no ceiling")
mounts = {m.get("mountPath"): m.get("name") for m in (v.get("additionalVolumeMounts") or [])}
vol_name = mounts.get(tmpdir) if tmpdir else None
if tmpdir and not vol_name:
    findings.append(f"TMPDIR is {tmpdir} but nothing is mounted there: the root filesystem is read-only, "
                    "so every buffered request would fail")
vols = {x.get("name"): x for x in ((v.get("deployment") or {}).get("additionalVolumes") or [])}
vol = vols.get(vol_name) if vol_name else None
if vol_name and not vol:
    findings.append(f"the mount at {tmpdir} names a volume «{vol_name}» that deployment.additionalVolumes "
                    "does not declare")
if vol is not None:
    limit = ((vol.get("emptyDir") or {}).get("sizeLimit")) if isinstance(vol.get("emptyDir"), dict) else None
    if not limit:
        findings.append(f"the buffer volume «{vol_name}» has no sizeLimit: orphaned buffers pile up "
                        "until the disk is full (9.7 GB on 2026-09-27)")
    elif not re.fullmatch(r"\d+(Mi|Gi)", str(limit)):
        findings.append(f"the buffer volume's sizeLimit «{limit}» is not a Mi/Gi quantity")

for x in findings:
    print(x)
print(f"SCOPE: traefik values: TMPDIR={tmpdir} → volume {vol_name} "
      f"({(vol or {}).get('emptyDir', {}).get('sizeLimit') if isinstance((vol or {}).get('emptyDir'), dict) else 'no ceiling'})")
