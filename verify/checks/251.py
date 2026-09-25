"""Check 251 — every public route has a streaming sibling that does not buffer the response.

2026-09-25, conf on the home instance: traefik's `buffering` middleware
(the org's `-cuerpo`, a 10 MiB cap on request bodies) also holds the
RESPONSE until it ends. The hub's SSE answered at once straight to the pod
and sent nothing in 4 s through traefik: a stream never ends, so it never
arrives. Driven: a contract is rendered through the real generator and
the IngressRoute is read.
"""
import os
import sys
import tempfile

import yaml

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []
PLANS = os.path.join(ROOT, "seed", "platform", "plans.yaml")
CONTRACT = """version: 1
organizacion: flujo
dominio: flujo.example.org
cuota: pequena
repo: acme/flujo
servicios:
  - {nombre: web, tipo: estatico, publico: /}
  - {nombre: api, tipo: http, puerto: 8080, publico: /api}
"""
with tempfile.TemporaryDirectory() as tmp:
    os.environ["AEGIS_CONF"] = os.path.join(tmp, "aegis.conf")
    open(os.environ["AEGIS_CONF"], "w").write('EDGE="local"\nAI="no"\n')
    from aegis import org
    plans = yaml.safe_load(open(PLANS, encoding="utf-8"))
    c = org.validate(yaml.safe_load(CONTRACT), plans)
    files, _ = org.render(c, plans, CONTRACT)
docs = [d for d in yaml.safe_load_all(files["routes.yaml"]) if d]
ir = next((d for d in docs if d.get("kind") == "IngressRoute"), None)
if not ir:
    print("the organization renders no IngressRoute: this check lost its subject")
    sys.exit(0)
routes = ir["spec"]["routes"]
mw = lambda r: [m["name"] for m in r.get("middlewares") or []]
svc = lambda r: (r.get("services") or [{}])[0].get("name")
plain = [r for r in routes if "text/event-stream" not in r["match"]]
stream = [r for r in routes if "text/event-stream" in r["match"]]
for r in plain:
    if "flujo-cuerpo" not in mw(r):
        findings.append(f"the route {r['match']!r} lost the body cap")
    sib = [x for x in stream if x["match"].startswith(f"({r['match']}) &&") and svc(x) == svc(r)]
    if not sib:
        findings.append(f"the route {r['match']!r} has no streaming sibling: its SSE and WebSockets go through the buffering and never arrive")
        continue
    x = sib[0]
    m = x["match"]
    if "flujo-cuerpo" in mw(x):
        findings.append(f"the streaming sibling of {r['match']!r} carries the buffering middleware: the stream is held until it ends")
    for need, why in (("Method(`GET`)", "without GET in the rule, a POST borrows the header and skips the 10 MiB cap"),
                      ("HeaderRegexp(`Upgrade`, `(?i)^websocket$`)", "WebSocket upgrades are not routed around the buffering"),
                      ("flujo-ritmo", None), ("flujo-cabeceras", None)):
        where = mw(x) if need.startswith("flujo-") else m
        if need not in where:
            findings.append(f"the streaming sibling of {r['match']!r} lacks {need}" + (f": {why}" if why else ""))
if len(stream) != len(plain):
    findings.append(f"{len(stream)} streaming routes for {len(plain)} public routes")
for f in findings:
    print(f)
print(f"SCOPE: {len(plain)} public routes rendered, {len(stream)} streaming siblings read")
