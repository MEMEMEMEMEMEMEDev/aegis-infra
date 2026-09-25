"""Check 245 — a release does not drop the people on the site.

2026-09-24, plan/19 B-8: under 300 req/s every rollout of the canary lost
~296 requests in 3 s (502s and 10 s hangs), measured on the cloud instance
and reproduced on Debian (295). The pod leaves the endpoints and stops at
the same instant, and traefik keeps routing to it until the change reaches
it. Neither the canary nor any app template carried a preStop.

Read: every Deployment the product ships for a TENANT (the canary and
every template's app) whose container declares a port.
"""
import pathlib
import sys

import yaml

root = pathlib.Path(sys.argv[1])
files = [root / "seed/canary/k8s/base/deployment.yaml"] + sorted(
    (root / "seed/templates").glob("*/repos/app/k8s/base/deployment.yaml"))
findings = []
serving = 0
MIN_SLEEP = 3

for f in files:
    rel = f.relative_to(root)
    try:
        docs = [d for d in yaml.safe_load_all(f.read_text()) if isinstance(d, dict)]
    except Exception as e:                               # noqa: BLE001
        findings.append(f"{rel} does not parse ({e})")
        continue
    for d in docs:
        if d.get("kind") != "Deployment":
            continue
        pod = d["spec"]["template"]["spec"]
        grace = pod.get("terminationGracePeriodSeconds", 30)
        for c in pod.get("containers") or []:
            if not c.get("ports"):
                continue                     # a worker: no endpoints, nobody to drop
            serving += 1
            pre = ((c.get("lifecycle") or {}).get("preStop") or {})
            secs = (pre.get("sleep") or {}).get("seconds")
            if pre.get("exec") and not pre.get("sleep"):
                findings.append(f"{rel}: preStop by exec — the runtime images carry no shell, "
                                "the hook fails and the pod stops at once")
            elif secs is None:
                findings.append(f"{rel}: container {c.get('name')} serves port(s) and has no preStop "
                                "sleep — every release drops the requests in flight (~3 s measured)")
            elif int(secs) < MIN_SLEEP:
                findings.append(f"{rel}: preStop sleeps {secs}s, less than the endpoint propagation "
                                f"measured ({MIN_SLEEP}s)")
            elif int(grace) <= int(secs):
                findings.append(f"{rel}: terminationGracePeriodSeconds {grace} is not longer than "
                                f"the preStop sleep {secs}: the kill lands before the app closes")

if serving < 5:
    findings.append(f"only {serving} serving deployments were read: the scan read less than the "
                    "canary and the five serving templates")

for x in findings:
    print(x)
print(f"SCOPE: {serving} serving deployments of {len(files)} files (canary + templates)")
