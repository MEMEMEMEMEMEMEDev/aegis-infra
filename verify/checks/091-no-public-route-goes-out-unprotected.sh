# title: no public route goes out to the world unprotected: Access in front or the three middlewares (#81/#90)
# origin: verify-static.sh (v2) ══ 91
check() {
# SPLIT in v3: this file measures the DISJUNCTION (Access or the three
# middlewares). That the canary's hand-written copies are still byte for
# byte what the generator emits is measured in 091b — they were two
# different questions in a single verdict, and when the second one lost
# its subject (org-blog lives in the instance, not in the artifact) it
# took the first one down with it.
# Until 2026-08-13 the cluster had ZERO middlewares: the public sites
# did not send a single security header, there was no rate limit and no
# body size limit.
#
# This check covers the TWO ways for that to come back without anybody
# noticing, and they are different:
#
#   a) a new route without the middleware list. The list goes PER
#      ROUTE (traefik has no «IngressRoute middlewares»), so adding a
#      `publico:` and forgetting leaves that route bare while the
#      others in the same file are protected.
#
#   b) the canary. Its routing is the ONLY hand-written one —it has no
#      contract to derive from, on purpose— so its three middlewares
#      are a COPY of the ones the generator emits. A copy nobody
#      compares drifts; this one is compared.
#
#   c) the PLATFORM routes (k8s/base/** of the SEED — B4, phase-85 §5).
#      The full doctrine is a DISJUNCTION: either the hostname is
#      behind Access (derived from the module's .tf files, like check
#      90 — never a list baked in here) or the route carries the three
#      middlewares. grafana complies through Access and goes without
#      middlewares; ntfy cannot go behind Access (the phone app does
#      not authenticate against Cloudflare) and complies through the
#      three — which additionally enter comparison (b), because they
#      are another hand-written copy of what the generator emits.
D91=""
python3 - "$P/k8s/organizations" "$P/k8s/base" \
    "$P/tofu/modules/cloudflare-access" <<'PY' || D91="$D91 (see the detail above);"
import re, sys, pathlib, yaml

root = pathlib.Path(sys.argv[1])
if not root.is_dir():
    print(f"    {root} does not exist", file=sys.stderr); sys.exit(1)

specs, bad = {}, []
for routes_file in sorted(root.glob("*/routes.yaml")):
    org = routes_file.parent.name
    docs = [d for d in yaml.safe_load_all(routes_file.read_text()) if d]
    mws = {d["metadata"]["name"]: d["spec"]
           for d in docs if d.get("kind") == "Middleware"}
    routes = [r for d in docs if d.get("kind") == "IngressRoute"
              for r in d["spec"].get("routes", [])]

    # (a) every route with the three, and referencing middlewares that
    #     EXIST in this same file. A reference to a nonexistent name is
    #     not a loud error in traefik: the route simply ends up without
    #     that middleware and keeps serving.
    for r in routes:
        used = [m["name"] for m in r.get("middlewares", []) or []]
        missing = [s for s in ("cabeceras", "ritmo", "cuerpo")
                   if not any(u.endswith("-" + s) for u in used)]
        if missing:
            bad.append(f"{org}: the route {r['match'][:40]!r} does not carry {missing}")
        for u in used:
            if u not in mws:
                bad.append(f"{org}: the route references middleware {u!r} which does NOT exist in its routes.yaml")

    # (b) the content, indexed by suffix so it can be compared across
    #     organizations (blog-ritmo vs canary-ritmo).
    for name, spec in mws.items():
        specs.setdefault(name.rsplit("-", 1)[-1], {})[org] = spec

# (c) platform: every IngressRoute in the seed's k8s/base/**, under the
#     Access-or-middlewares disjunction. The list of hostnames behind
#     Access is DERIVED from the seed's module (all the .tf files: HCL
#     merges the directory, and grafana.tf is a file of its own).
base, module = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
behind_access = set()
for tf in sorted(module.glob("*.tf")):
    behind_access |= set(re.findall(
        r'^\s*domain\s*=\s*"([a-z0-9-]+)\.\$\{var\.root_domain\}',
        tf.read_text(), re.M))
if not behind_access:
    bad.append(f"the Access module in {module} declares no domain "
               "— without that list the disjunction cannot be evaluated")
n_plat = 0
for f in sorted(base.rglob("*.yaml")):
    docs = [d for d in yaml.safe_load_all(f.read_text())
            if isinstance(d, dict)]
    if not any(d.get("kind") == "IngressRoute" for d in docs):
        continue
    rel = f.relative_to(base)
    mws = {d["metadata"]["name"]: d["spec"]
           for d in docs if d.get("kind") == "Middleware"}
    for d in docs:
        if d.get("kind") != "IngressRoute":
            continue
        for r in d["spec"].get("routes", []):
            n_plat += 1
            hosts = re.findall(r"Host\(`([a-z0-9-]+)\.", r.get("match", ""))
            if hosts and all(h in behind_access for h in hosts):
                continue        # the door is put there by Cloudflare, not traefik
            used = [m["name"] for m in r.get("middlewares", []) or []]
            missing = [s for s in ("cabeceras", "ritmo", "cuerpo")
                       if not any(u.endswith("-" + s) for u in used)]
            if missing:
                bad.append(f"base/{rel}: the route {r.get('match', '')[:40]!r} "
                           f"is not behind Access ({'/'.join(sorted(behind_access))}) "
                           f"nor does it carry {missing}")
            for u in used:
                if u not in mws:
                    bad.append(f"base/{rel}: the route references middleware "
                               f"{u!r} which does NOT exist in its file")
    # its copies of the three middlewares enter comparison (b); ONLY
    # those three suffixes: a middleware of another class in base/ has
    # no reference in the generator to be held to.
    for name, spec in mws.items():
        pref, _, suf = name.rpartition("-")
        if suf in ("cabeceras", "ritmo", "cuerpo"):
            specs.setdefault(suf, {})[pref] = spec
print(f"    {n_plat} platform routes in {base.name}/ under the disjunction "
      f"Access({len(behind_access)} hostnames) or middlewares", file=sys.stderr)

for m in bad:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D91" ]]; then fail "edge middlewares:$D91"
else pass "every public route (organizations and platform) goes behind Access or carries cabeceras+ritmo+cuerpo"; fi
}
