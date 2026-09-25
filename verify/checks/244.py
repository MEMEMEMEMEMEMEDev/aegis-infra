"""Check 244 — every rate limiter counts per visitor, and traefik has room.

2026-09-24, plan/19 L3 on the cloud instance, with a control: behind the
Cloudflare tunnel every connection traefik sees comes from cloudflared,
and a rateLimit without a sourceCriterion counts by the CONNECTION. The
limit «per visitor» was one bucket for the whole internet: a quiet visitor
at ~5 req/s got 197 × 429 of 300 while another IP pushed 80 req/s, and
0 × 429 alone. The generator's comment claimed the opposite for six weeks.

And traefik, the one door every tenant shares, ran 1 replica with 256Mi:
OOMKilled at ~1600 req/s towards a CPU-throttled backend (B-3).

Driven: the generator renders a probe organization's routes and the
middleware it emits is read like the seed's.
"""
import os
import pathlib
import sys

import yaml

root = pathlib.Path(sys.argv[1])
seed = root / "seed" / "platform"
findings = []
seen = 0

vals_path = seed / "k8s/base/ingress/traefik/values.yaml"
vals = yaml.safe_load(vals_path.read_text())
trusted = set()
for port in (vals.get("ports") or {}).values():
    trusted |= set(((port or {}).get("forwardedHeaders") or {}).get("trustedIPs") or [])
if not trusted:
    findings.append("traefik's values trust no forwarded range: there is nothing a rate limiter "
                    "could exclude, and no visitor IP to count by")


def judge(doc, where):
    global seen
    rl = ((doc or {}).get("spec") or {}).get("rateLimit")
    if doc is None or doc.get("kind") != "Middleware" or rl is None:
        return
    seen += 1
    name = (doc.get("metadata") or {}).get("name", "?")
    ex = (((rl.get("sourceCriterion") or {}).get("ipStrategy") or {}).get("excludedIPs"))
    if not ex:
        findings.append(f"{where}: middleware {name} limits without a sourceCriterion — behind the "
                        "tunnel it counts by cloudflared's address: ONE bucket for the whole internet")
    elif set(ex) != trusted:
        findings.append(f"{where}: middleware {name} excludes {sorted(ex)} but traefik trusts "
                        f"{sorted(trusted)}: the visitor it picks out of X-Forwarded-For is not the one "
                        "the entrypoints vouch for")


for f in sorted(seed.rglob("*.yaml")):
    try:
        docs = list(yaml.safe_load_all(f.read_text()))
    except Exception:
        continue
    for d in docs:
        if isinstance(d, dict):
            judge(d, str(f.relative_to(root)))

os.environ["AEGIS_ROOT"] = str(root)
sys.path.insert(0, str(root / "lib"))
try:
    from aegis import org as gen
    probe = {"version": 1, "organizacion": "probe", "dominio": "probe.example.cl", "cuota": "pequena",
             "servicios": [{"nombre": "web", "tipo": "http", "puerto": 8080, "publico": "/",
                            "repo": "git@github.com:probe/web.git"}]}
    out = gen.render_routes(probe, "0" * 12)
    n0 = seen
    for d in yaml.safe_load_all(out):
        if isinstance(d, dict):
            judge(d, "the generator (render_routes)")
    if seen == n0:
        findings.append("the generator rendered a public organization and emitted no rateLimit at all")
except Exception as e:                                   # noqa: BLE001
    findings.append(f"the generator's routes could not be rendered for a probe organization ({e})")

if seen < 3:
    findings.append(f"only {seen} rate limiters were found (the seed's canary and ntfy, plus the "
                    "generator's): the scan read less than it should")

dep = vals.get("deployment") or {}
if int(dep.get("replicas") or 1) < 2:
    findings.append("traefik runs ONE replica: when it is OOMKilled the whole edge goes dark with it")


def mib(v):
    v = str(v)
    for suf, k in (("Gi", 1024), ("Mi", 1), ("G", 1000), ("M", 1)):
        if v.endswith(suf):
            return float(v[: -len(suf)]) * k
    return float(v) / 2**20


lim = ((vals.get("resources") or {}).get("limits") or {}).get("memory")
if lim is None or mib(lim) < 512:
    findings.append(f"traefik's memory limit is {lim}: it was OOMKilled at 256Mi under load (B-3)")

for f in findings:
    print(f)
print(f"SCOPE: {seen} rate limiters (seed + generator) against traefik's trusted range "
      f"{sorted(trusted)}, and traefik's replicas and memory")
