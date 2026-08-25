# title: the hand-written copies of the middlewares are what the generator emits
# origin: verify-static.sh (v2) ══ 91, part (b) — split off in v3
check() {
# The canary has no contract (it is what proves the tenant's path
# works, so it cannot depend on that path), but it needs the three
# middlewares all the same. They are written BY HAND in its
# routes.yaml, and they have to be the ones `aegis org` generates for
# any organization with a contract: if somebody touches the generator
# and forgets the copy, the canary is left with the old protection and
# nobody finds out. The same goes for ntfy in the platform's own
# routes.yaml — it cannot go behind Access (the phone app does not
# authenticate against Cloudflare), so it complies through the three,
# hand-written too.
#
# In v2 the reference was `org-blog`: a REAL organization of the
# instance, committed in platform/k8s/organizations/. Two problems that
# are only visible from v3: the artifact has no org-blog (nor should it
# — the seed carries no instance inside it, check 86), and a reference
# tied to a concrete name lies the day that organization is deleted.
# The correct reference is not another copy: it is THE GENERATOR.
#
# WHY «what it emits» AND NOT «byte for byte». The copies are
# deliberately NOT a byte-for-byte transcript: the canary strips the
# generator's comments and writes its own explaining why it is
# hand-written, and its route serves `hello-aegis:80` instead of the
# `<org>-<service>:8080` convention (it predates the convention, and
# aligning it would mean touching the repo that serves as the reference
# for checking that the tenant's path still works). What has to be
# identical is what PROTECTS: the three `spec:` bodies. Comparing text
# would tie the check to the prose and it would go red on any rewording
# — a check that cries wolf about comments gets silenced, and then it
# is not there the day the rate limit really moves.
#
# HISTORY, because it is the point of this file: between 2026-08-23 and
# 2026-08-25 this check evaluated NOTHING. It was written as a debt
# that collects itself — «skip until lib/aegis/derivar.py exists» —
# and the module was born under another name (`aegis.org`). The probe
# never matched, the check skipped for ever, and the promise expired in
# silence. A debt that collects itself only works if the collector
# knows the debtor's name.
D91B=""
python3 - "$AEGIS_ROOT" "$P" <<'PY' || D91B=" (see the detail above)"
import sys, os, pathlib, yaml

root, P = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

# An instrument leaves no trace on the subject: importing the generator
# would write __pycache__/ inside the very tree the verifier measures,
# and on 2026-08-24 that turned check 105 red (it read the banner
# inside a .pyc and reported it as a hand-written copy).
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
os.environ["PLATFORM_DIR"] = str(P)
sys.path.insert(0, str(root / "lib"))
try:
    from aegis import org as gen
except Exception as e:
    print(f"    the product's generator does not load: {e}", file=sys.stderr)
    sys.exit(1)
if not hasattr(gen, "render_routes"):
    print("    lib/aegis/org.py has no render_routes(): the reference this "
          "check compares against no longer exists under that name",
          file=sys.stderr)
    sys.exit(1)

# A synthetic contract, minimal and valid: the middlewares do not
# depend on a single one of its values (only the `<org>-` prefix of the
# name does), so anything that renders serves as the reference. It is
# NOT read from the seed on purpose — the reference has to be the
# generator's code, never another file that could drift with it.
contract = {"version": 1, "organizacion": "reference",
            "dominio": "reference.example.com", "cuota": "pequena",
            "repo": "git@github.com:owner/repo.git",
            "servicios": [{"nombre": "front", "tipo": "estatico",
                           "publico": "/"}]}
try:
    emitted = gen.render_routes(contract, "sha256:0000000000000000")
except Exception as e:
    print(f"    render_routes() blew up on a minimal contract: {e}",
          file=sys.stderr)
    sys.exit(1)
if not emitted:
    print("    render_routes() returned nothing for a contract WITH a public "
          "service — there is no reference to compare against", file=sys.stderr)
    sys.exit(1)

reference = {d["metadata"]["name"].rsplit("-", 1)[-1]: d["spec"]
             for d in yaml.safe_load_all(emitted)
             if isinstance(d, dict) and d.get("kind") == "Middleware"}
THREE = ("cabeceras", "ritmo", "cuerpo")
missing_ref = [s for s in THREE if s not in reference]
if missing_ref:
    print(f"    the generator no longer emits {missing_ref}: either the edge "
          "doctrine changed and this check was not brought along, or the "
          "middlewares lost their name", file=sys.stderr)
    sys.exit(1)


def difference(want, got, path=""):
    """The first divergence, named by its key path.

    A boolean verdict would send whoever reads it to diff two YAMLs by
    eye. The failure this check exists for is a NUMBER that moved (a
    rate limit, a body size), so the message has to carry the number.
    """
    if isinstance(want, dict) and isinstance(got, dict):
        for k in sorted(set(want) | set(got)):
            if k not in got:
                return f"{path}.{k} is missing (the generator emits it)"
            if k not in want:
                return f"{path}.{k} is left over (the generator does not emit it)"
            d = difference(want[k], got[k], f"{path}.{k}")
            if d:
                return d
        return None
    if want != got:
        return f"{path or 'spec'}: the generator says {want!r}, the copy says {got!r}"
    return None


# Every hand-written copy in the seed, found by SHAPE and not by a list
# of paths: a copy that is born in a new file has to enter the
# comparison on its own, without anybody remembering to add it here.
bad, n, owner_of, found_in = [], 0, {}, {}
files = sorted(P.glob("k8s/organizations/*/routes.yaml")) + \
        sorted(P.glob("k8s/base/**/*.yaml"))
for f in files:
    try:
        docs = [d for d in yaml.safe_load_all(f.read_text())
                if isinstance(d, dict)]
    except yaml.YAMLError:
        continue            # its own YAML validity is check 002's business
    # who the file says it belongs to, taken from its IngressRoute
    owners = {(d.get("metadata") or {}).get("labels", {}).get("aegis.dev/part-of")
              for d in docs if d.get("kind") == "IngressRoute"}
    owners.discard(None)
    if len(owners) == 1:
        owner_of[f] = owners.pop()

    for d in docs:
        if d.get("kind") != "Middleware":
            continue
        name = (d.get("metadata") or {}).get("name", "")
        suffix = name.rsplit("-", 1)[-1]
        if suffix not in reference:
            continue        # a middleware of another class has no reference
        n += 1
        found_in.setdefault(f, set()).add(suffix)
        rel = f.relative_to(P)
        diff = difference(reference[suffix], d.get("spec"))
        if diff:
            bad.append(f"{rel}: {name} has drifted from render_routes() — {diff}")
        # The owner label is DERIVED from the file, never a list of
        # allowed values baked in here: the copy under
        # k8s/organizations/ belongs to `aegis-organizaciones` and the
        # one under k8s/base/ to `aegis-platform`, and hardcoding both
        # would be one more hand-kept list to rot. What has to hold is
        # that a route and ITS middlewares are attributable to the same
        # owner — `aegis check` lists routes by that label, and a
        # middleware that loses it drops out of every inventory while
        # still serving.
        labels = (d.get("metadata") or {}).get("labels") or {}
        mine = labels.get("aegis.dev/part-of")
        if owner_of.get(f) and mine != owner_of[f]:
            bad.append(f"{rel}: {name} carries aegis.dev/part-of: {mine!r} "
                       f"but the IngressRoute in its own file carries "
                       f"{owner_of[f]!r} — a route and its middlewares are "
                       "one unit and have to be attributable to one owner")

# A copy that DISAPPEARS was invisible to the comparison above: it only
# looks at the middlewares that exist, so deleting one just left one
# fewer to compare and everything stayed green. Its own tooth denounced
# it on 2026-08-25. The generator emits the three as a set, so the set
# is what has to be complete: a file that carries one of them and not
# the other two is a site that lost protection, and the route that
# still cites the missing one keeps serving — traefik ignores a
# dangling middleware reference without a word.
for f, present in sorted(found_in.items(), key=lambda kv: str(kv[0])):
    absent = [s for s in reference if s not in present]
    if absent:
        bad.append(f"{f.relative_to(P)}: carries {sorted(present)} but NOT "
                   f"{absent} — the generator emits the three as a set, and a "
                   "route that cites a middleware that does not exist is "
                   "served unprotected without a single error")

if n == 0:
    print("    NOT ONE hand-written copy was found: either they were all "
          "deleted or they stopped being called <name>-cabeceras/-ritmo/"
          "-cuerpo, and this check was measuring nothing", file=sys.stderr)
    sys.exit(1)

print(f"    {n} hand-written copies compared against render_routes()",
      file=sys.stderr)
for m in bad:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D91B" ]]; then
    fail "a hand-written copy of the middlewares no longer matches the generator$D91B"
else
    pass "every hand-written copy of the three middlewares is what render_routes() emits"
fi
}
