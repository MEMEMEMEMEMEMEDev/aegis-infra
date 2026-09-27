"""Check 251 — every public route has a read-only sibling (GET, HEAD) that does not buffer the response.

2026-09-25, conf on the home instance: traefik's `buffering` middleware
(the org's `-cuerpo`, a 10 MiB cap on request bodies) also holds the
RESPONSE until it ends. The hub's SSE answered at once straight to the pod
and sent nothing in 4 s through traefik: a stream never ends, so it never
arrives.

2026-09-27, drop on the same instance: the sibling only caught GETs that
announced a stream (`Accept: text/event-stream`, a WebSocket upgrade), so
a plain download of a 3 GB file was still buffered — copied in full to a
`temp-multibuf-*` file in traefik's emptyDir on the system SSD before the
first byte went out. That disk also carries the k3s datastore: it sat at
90 % busy, the API server slowed to seconds, traefik and kyverno failed
their liveness and were killed, and the download died with the tunnel.
Every GET and HEAD now goes around the buffering: neither carries a body,
so the cap has nothing to cap there. Driven: a contract is rendered
through the real generator and the IngressRoute is read.
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
# The plain route names no method; the sibling is the one that does.
plain = [r for r in routes if "Method(" not in r["match"]]
reads = [r for r in routes if "Method(" in r["match"]]
for r in plain:
    if "flujo-cuerpo" not in mw(r):
        findings.append(f"the route {r['match']!r} lost the body cap")
    sib = [x for x in reads if x["match"].startswith(f"({r['match']}) &&") and svc(x) == svc(r)]
    if not sib:
        findings.append(f"the route {r['match']!r} has no read-only sibling: its downloads and streams go through the buffering — a file is copied to disk in full, a stream never arrives")
        continue
    x = sib[0]
    m = x["match"]
    if "flujo-cuerpo" in mw(x):
        findings.append(f"the read-only sibling of {r['match']!r} carries the buffering middleware: the response is held until it ends")
    for need, why in (("Method(`GET`)", "without GET in the rule, a POST borrows the route and skips the 10 MiB cap"),
                      ("Method(`HEAD`)", "a HEAD (what a download manager or a Range probe sends first) is still buffered"),
                      ("flujo-ritmo", None), ("flujo-cabeceras", None)):
        where = mw(x) if need.startswith("flujo-") else m
        if need not in where:
            findings.append(f"the read-only sibling of {r['match']!r} lacks {need}" + (f": {why}" if why else ""))
    # A method other than GET/HEAD in the rule would let a body-carrying
    # request around the cap; the rule may name those two and nothing else.
    for bad in ("POST", "PUT", "PATCH", "DELETE"):
        if f"Method(`{bad}`)" in m:
            findings.append(f"the read-only sibling of {r['match']!r} admits {bad}, which carries a body: the 10 MiB cap is skipped")
if len(reads) != len(plain):
    findings.append(f"{len(reads)} read-only routes for {len(plain)} public routes")
for f in findings:
    print(f)
print(f"SCOPE: {len(plain)} public routes rendered, {len(reads)} read-only siblings read")
