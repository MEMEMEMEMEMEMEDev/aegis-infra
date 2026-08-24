# title: every seed with a Service declares its EXPOSURE (CR-5 generalization)
# origin: verify-static.sh (v2) ══ 55
check() {
# CR-5 was statically detectable: an app with a Service and no
# IngressRoute is born invisible from the edge. Nobody sees it fail: the
# manifest is perfect and the traffic does not arrive.
#
# The original rule was "IngressRoute IN THE SAME TREE", and with #54 it
# stopped holding: the route moved next to the platform precisely so
# that the app's repo cannot write it. Looking for it where it can no
# longer be would turn the fix into a red.
#
# The invariant did not change — "something routes to that Service" —,
# what changed is where that something lives. It is searched BY SERVICE
# NAME across the WHOLE seed: the app's tree and
# k8s/organizations/*/routes.yaml. What matters is that a route exists,
# not who writes it.
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); ok = True

def docs(f):
    try:
        for d in yaml.safe_load_all(f.open()):
            if d and isinstance(d, dict):
                yield d
    except Exception:
        return

# Every Service pointed at by SOME IngressRoute in the seed, whether it
# lives in the app's repo or on the platform side.
routed = set()
for f in (root/"seed").rglob("*.y*ml"):
    for d in docs(f):
        if d.get("kind") != "IngressRoute":
            continue
        for r in (d.get("spec") or {}).get("routes") or []:
            for s in r.get("services") or []:
                if s.get("name"):
                    routed.add(s["name"])

evaluated = 0
for app in (root/"seed").iterdir():
    # `templates` is not an app seed either: it is evaluated separately,
    # below, because its exposure lives in another file (the template
    # contract).
    if not app.is_dir() or app.name in ("platform", "templates"):
        continue
    services, texts = set(), []
    for f in app.rglob("*.y*ml"):
        texts.append(f.read_text())
        for d in docs(f):
            if d.get("kind") == "Service":
                services.add(d["metadata"]["name"])
    if not services:
        continue
    evaluated += 1
    if any("expose: false" in t for t in texts):
        continue
    orphans = services - routed
    if orphans:
        print(f"FAIL seed {app.name}: Service(s) {sorted(orphans)} with no "
              f"IngressRoute naming them (neither here nor in the platform) "
              f"and no explicit 'expose: false'")
        ok = False
# Templates (caminos/design.md §4) carry the SAME invariant in ANOTHER
# form: their IngressRoute cannot exist in the seed because aegis-org
# derives it FROM THE CONTRACT at instantiation time (#54 — the kind
# does not even belong to the app's repo). What the template can and
# must declare is the exposure: a skeleton with a Service whose
# contract.yaml.tpl does not say `publico:` would instantiate apps that
# are born invisible — exactly the CR-5 this check exists to hunt.
tpls = root/"seed"/"templates"
if tpls.is_dir():
    for p in sorted(tpls.iterdir()):
        if not p.is_dir():
            continue
        services, texts = set(), []
        for f in p.rglob("*.y*ml"):
            texts.append(f.read_text())
            for d in docs(f):
                if d.get("kind") == "Service":
                    services.add(d["metadata"]["name"])
        if not services:
            continue
        evaluated += 1
        if any("expose: false" in t for t in texts):
            continue
        tpl = p/"contract.yaml.tpl"
        if "publico:" not in (tpl.read_text() if tpl.exists() else ""):
            print(f"FAIL template {p.name}: skeleton with Service(s) "
                  f"{sorted(services)} and a contract.yaml.tpl without `publico:` — "
                  f"every instantiated app would be born invisible from the edge (CR-5)")
            ok = False
# A sweep that swept nothing is not a verdict: if no seed declares
# Services, this check stopped measuring and we need to find out.
if evaluated == 0:
    print("FAIL no seed with a Service: check 55 evaluated nothing")
    ok = False
# P2.12: the canary with 1 replica CANNOT have a rollout window:
dep = yaml.safe_load_all((root/"seed"/"canary"/"k8s/base/deployment.yaml").open())
d = next(x for x in dep if x and x.get("kind") == "Deployment")
ru = ((d["spec"].get("strategy") or {}).get("rollingUpdate") or {})
if ru.get("maxUnavailable") != 0:
    print("FAIL canary without maxUnavailable: 0 (Bad Gateway window with 1 replica)")
    ok = False
sys.exit(0 if ok else 1)
EOF
then pass "seeds with a Service expose it (or declare expose: false); canary with no rollout window"
else fail "a seed is born invisible from the edge or with rollout downtime (CR-5/P2.12)"; fi
}
