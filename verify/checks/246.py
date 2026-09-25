"""Check 246 — traefik gives up on a dead backend instead of hanging the visitor.

2026-09-24, plan/19 N2: a 90 s network cut between traefik and the canary
(Chaos Mesh partition). With no ServersTransport and no forwarding
timeouts, traefik v3.7.4 dials for 30 s and waits for response headers
with no limit (its own --help: dialtimeout 30, responseheadertimeout 0):
every visitor hung until their client gave up.

Read: traefik's values, the one place its static arguments come from.
"""
import pathlib
import re
import sys

import yaml

root = pathlib.Path(sys.argv[1])
vals_path = root / "seed/platform/k8s/base/ingress/traefik/values.yaml"
vals = yaml.safe_load(vals_path.read_text())
args = [str(a) for a in (vals.get("additionalArguments") or [])]
findings = []


def arg(name):
    pat = re.compile(r"^--serverstransport\.forwardingtimeouts\." + name + r"=(\S+)$", re.I)
    got = [pat.match(a).group(1) for a in args if pat.match(a)]
    return got[-1] if got else None


def seconds(v):
    m = re.fullmatch(r"(\d+(?:\.\d+)?)(ms|s|m)?", v or "")
    if not m:
        return None
    n = float(m.group(1)); u = m.group(2) or "s"
    return n / 1000 if u == "ms" else n * 60 if u == "m" else n


dial, rh = arg("dialtimeout"), arg("responseheadertimeout")
if dial is None:
    findings.append("traefik has no dialTimeout: it dials a dead backend for 30 s (the binary's default)")
elif seconds(dial) is None or seconds(dial) > 10:
    findings.append(f"traefik's dialTimeout is {dial}: a same-node connect answers in milliseconds, "
                    "and more than 10 s keeps the visitor hanging on a dead pod")
if rh is None:
    findings.append("traefik has no responseHeaderTimeout: it waits for headers FOREVER (default 0)")
else:
    s = seconds(rh)
    if s is None or s <= 0:
        findings.append(f"traefik's responseHeaderTimeout is {rh}: zero means no limit")
    elif s >= 100:
        findings.append(f"traefik's responseHeaderTimeout is {rh}: at 100 s Cloudflare cuts first (524), "
                        "and the visitor never sees traefik's own answer")
    elif s < 30:
        findings.append(f"traefik's responseHeaderTimeout is {rh}: short enough to cut legitimate slow "
                        "requests that have not sent headers yet")

for f in findings:
    print(f)
print(f"SCOPE: {len(args)} static argument(s) of traefik read from its values "
      f"(dialTimeout={dial}, responseHeaderTimeout={rh})")
