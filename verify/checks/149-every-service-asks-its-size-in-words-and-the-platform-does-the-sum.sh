# title: every service asks for its size in a word, the platform adds the sizes against the quota, and the tenant cannot take the pen back
# origin: new in v3 — 2026-08-29, a service's resources lived in the tenant's repo: 50m/32Mi for everything, and that kills a JVM on start-up
check() {
# WHAT THIS PROTECTS, in the order the mechanism runs.
#
# 1. THE VOCABULARY. A contract says `tamano: mediano` and names no
#    number; the numbers live in plans.yaml. That inversion only holds
#    while the words on both sides are the same words. If a size
#    disappears from plans.yaml —renamed, tidied away, lost in a
#    merge— every contract that asks for it STOPS VALIDATING, and the
#    contracts do not live in this repo: they live in each instance, so
#    nothing else in this tree would turn red.
#
# 2. THE REJECTIONS. A size plans.yaml does not carry has to be refused
#    HERE. And a plans.yaml with a HOLE in it —the adoption path this
#    field documents is «copy the section across by hand»— has to be an
#    Invalid naming the file, never a python traceback: a KeyError says
#    neither which file nor what is missing from it.
#
# 3. THE SUM. The whole point of the field is that the platform, not
#    the apiserver, tells you the services do not fit. Left to the
#    cluster the same mistake arrives as a ResourceQuota rejecting
#    whichever pod was scheduled last, hours later, in a message about
#    millicores.
#
# 4. THE OBJECTS. The LimitRange that fills in what a container did not
#    declare, and the namespaced Kyverno Policy that OVERRIDES what it
#    did declare, with the numbers of the size its contract asked for.
#    Deleting either of them leaves every check green: the harness
#    declares both as deliberate divergences from v2 —that is the point
#    of that list— so it is here, and only here, that their absence is
#    a failure.
#
# 5. THE PEN. The Policy is namespaced and lives in org-<org>, which is
#    the one namespace the tenant's AppProject may write. Without
#    `kyverno.io/Policy` in its namespaceResourceBlacklist the tenant
#    can ship a Policy of its own and undo the platform's numbers,
#    leaving only the ResourceQuota —the coarse wall `tamano` exists to
#    refine— holding.
#
# WHAT IS DERIVED AND WHAT IS TYPED, because the difference is the
# check's own honesty:
#   derived from lib/aegis/org.py  the four keys a size is made of
#                                  (SIZE_KEYS), the default a contract
#                                  gets when it names none
#                                  (DEFAULT_SIZE), and the table of
#                                  what a provided service asks for
#   derived from plans.yaml        which plan is the smallest and which
#                                  size the biggest — so the contract
#                                  that must NOT fit is built from the
#                                  file's own arithmetic and not from
#                                  numbers typed here, which would rot
#                                  the first time a plan is re-tuned
#   typed here                     the three size names. They are
#                                  contract VOCABULARY —a word somebody
#                                  may write in a file this repo will
#                                  never see— and there is nowhere else
#                                  to read them from that would not be
#                                  the very file under test.
D149=""
python3 - "$AEGIS_ROOT" "$P" <<'PY' || D149=" (see the detail above)"
import copy, os, pathlib, shutil, sys, tempfile

root, P = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

# A SCRATCH instance, not the seed. This check RENDERS, and
# render_appprojects() reads the contracts off disk: pointing the
# generator at the seed would mean writing a contract into the tree the
# verifier is measuring. An instrument leaves no trace on its subject.
tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-149-"))
(tmp / "orgs").mkdir()
os.environ["PLATFORM_DIR"] = str(tmp)
sys.path.insert(0, str(root / "lib"))
try:
    import yaml
    from aegis import org as gen
except Exception as e:                                   # noqa: BLE001
    print(f"    the product's generator does not load: {e}", file=sys.stderr)
    sys.exit(1)
shutil.copy(P / "services.yaml", tmp / "services.yaml")

DOCUMENTED = ("chico", "mediano", "grande")
bad = []
plans = yaml.safe_load((P / "plans.yaml").read_text(encoding="utf-8")) or {}
sizes = plans.get("tamano") or {}
quotas = plans.get("cuota") or {}


def contract(quota, servicios):
    return {"version": 1, "organizacion": "talla", "cuota": quota,
            "repo": "git@github.com:owner/repo.git", "servicios": servicios}


# ── 1. the vocabulary, and its four numbers ──────────────────────────
for name in DOCUMENTED:
    if name not in sizes:
        bad.append(f"plans.yaml declares no tamano `{name}`: every contract that "
                   f"asks for it stops validating, and the contracts are not in "
                   f"this repo")
if gen.DEFAULT_SIZE not in sizes:
    bad.append(f"the generator's default tamano is `{gen.DEFAULT_SIZE}` and "
               f"plans.yaml does not carry it: a contract that names no `tamano` "
               f"—which is every contract written before the field— would be "
               f"rejected for a word it never wrote")

for name in sorted(sizes):
    numbers = sizes[name] or {}
    for key in gen.SIZE_KEYS:
        if key not in numbers:
            bad.append(f"tamano `{name}` does not declare {key}: the LimitRange "
                       f"and the admission patch that come out of it would be "
                       f"written with a hole in them")
            continue
        # The value has to be a quantity THE GENERATOR can read, not one
        # a human recognises: it is the generator that adds these up
        # against the quota.
        read = gen._cpu if key.endswith(".cpu") else gen._mem
        try:
            if read(numbers[key]) <= 0:
                raise ValueError("not a positive quantity")
        except Exception as e:                           # noqa: BLE001
            bad.append(f"tamano `{name}`, {key}: {numbers[key]!r} is not a "
                       f"quantity this generator can add up ({e})")

# Everything below RENDERS and ADDS UP, so it needs a plans.yaml whose
# arithmetic can be done at all. Reporting the same hole twice helps
# nobody; the block above already named it.
usable = (not bad) and quotas and gen.DEFAULT_SIZE in sizes


def mem(d):
    return gen._mem(d["requests.memory"])


if not usable:
    print("    plans.yaml does not hold together: the render and the sum were "
          "not exercised", file=sys.stderr)
else:
    # Derived, never typed: the plan that gives least and the size that
    # asks most are what make the «does not fit» case real, and a number
    # typed here would rot the first time a step is re-tuned.
    smallest = min(quotas, key=lambda q: mem(quotas[q]))
    largest = max(quotas, key=lambda q: mem(quotas[q]))
    biggest = max(sizes, key=lambda s: mem(sizes[s]))
    # The contract everything that RENDERS below is built from: two
    # services that must not come out sized alike —one names a `tamano`
    # and the other takes the default— plus a database, which is what
    # the platform provides and the contract has no say over.
    svcs = [{"nombre": "api", "tipo": "worker", "tamano": biggest},
            {"nombre": "front", "tipo": "worker"},
            {"nombre": "datos", "tipo": "postgres"}]

    # ── 2a. a size plans.yaml does not carry is REFUSED ──────────────
    invented = "no-such-size"
    while invented in sizes:
        invented += "x"
    one = [{"nombre": "front", "tipo": "worker"}]
    try:
        gen.validate(contract(smallest, [dict(one[0], tamano=invented)]), plans)
        bad.append(f"the generator ACCEPTED `tamano: {invented}`, which plans.yaml "
                   f"does not carry: the service would be rendered with no size at "
                   f"all and the failure would land on the apiserver")
    except gen.Invalid as e:
        if "does not exist" not in str(e):
            bad.append(f"the generator rejects an unknown tamano for the WRONG "
                       f"reason: {str(e).splitlines()[0]!r}")
    except Exception as e:                               # noqa: BLE001
        bad.append(f"the generator did not reject an unknown tamano: it BROKE "
                   f"({type(e).__name__}: {str(e).splitlines()[0]})")
    # and the good one goes through, or a validator that rejected
    # everything would come out green on the line above. The SMALLEST
    # plan on purpose: the largest one would never exercise the sum.
    try:
        gen.validate(contract(smallest, [{"nombre": "front", "tipo": "worker"},
                                         {"nombre": "datos", "tipo": "postgres"}]),
                     plans)
    except Exception as e:                               # noqa: BLE001
        bad.append(f"a service of the default tamano plus a database does not fit "
                   f"in the smallest plan `{smallest}`: {str(e).splitlines()[0]}")

    # ── 2b. a plans.yaml with a HOLE is an Invalid, not a traceback ──
    #
    # This is the adoption path the field documents: an instance older
    # than the `tamano:` section copies it across BY HAND, and a copy
    # that brings only the steps that instance happens to use is a
    # partial copy. MEASURED before this block existed: with `chico`
    # deleted, a contract naming `grande` validated clean and died
    # inside render_bundle with KeyError('chico') — the LimitRange is
    # written from the default step whether or not anybody asked for it.
    def _drop_default(p):
        p["tamano"].pop(gen.DEFAULT_SIZE)

    def _half_default(p):
        p["tamano"][gen.DEFAULT_SIZE].pop("limits.memory")

    def _unreadable_size(p):
        p["tamano"][gen.DEFAULT_SIZE]["requests.memory"] = "a bit"

    def _half_quota(p):
        p["cuota"][smallest].pop("pods")

    def _unreadable_quota(p):
        p["cuota"][smallest]["limits.cpu"] = "plenty"

    HOLES = (
        ("the default size deleted", _drop_default),
        ("the default size missing one of its four numbers", _half_default),
        ("a size whose number nobody can add up", _unreadable_size),
        ("a quota plan missing one of its seven numbers", _half_quota),
        ("a quota plan whose number nobody can add up", _unreadable_quota),
    )
    for what, hole in HOLES:
        p = copy.deepcopy(plans)
        hole(p)
        try:
            gen.validate(contract(smallest, copy.deepcopy(one)), p)
        except gen.Invalid:
            continue
        except Exception as e:                           # noqa: BLE001
            bad.append(f"a plans.yaml with {what} does not give an Invalid: it "
                       f"BREAKS with {type(e).__name__}({e}). A traceback names "
                       f"neither the file nor what is missing from it, which is "
                       f"the whole reason the product rejects instead of crashing")
            continue
        bad.append(f"a plans.yaml with {what} was ACCEPTED: the hole surfaces "
                   f"later, as a traceback or as a manifest with a gap in it")

    # ── 2c. services.yaml decides a provided service, ALL FOUR OR NONE ──
    #
    # MEASURED on 2026-08-29 with the per-key fallback this replaced:
    # `request.memory` —one missing `s`— was dropped without a word and
    # the generator's own table won. The operator believes they resized
    # the database, the manifest carries the old figure, verify green.
    cat = yaml.safe_load((P / "services.yaml").read_text(encoding="utf-8"))
    table = gen.PLATFORM_RESOURCES["postgres"]

    def with_recursos(block):
        c2 = copy.deepcopy(cat)
        c2["tipos"]["postgres"]["recursos"] = block
        return c2

    # WITHOUT the block, whatever the seed's file happens to say today:
    # declaring `recursos:` there is legitimate —it is the file that
    # decides the image, the port and the disk— so the fallback is
    # measured on a copy with the block removed, never on the file as it
    # stands. Otherwise this check would forbid the very edit the
    # message below says is allowed.
    bare = copy.deepcopy(cat)
    (bare["tipos"]["postgres"] or {}).pop("recursos", None)
    if gen.platform_resources(bare, "postgres") != table:
        bad.append("with no `recursos:` in services.yaml the database does not "
                   "get the generator's table: the fallback moved and the sum "
                   "and the manifest can now disagree")
    four = {"requests.cpu": "250m", "requests.memory": "1Gi",
            "limits.cpu": "2", "limits.memory": "4Gi"}
    try:
        got = gen.platform_resources(with_recursos(four), "postgres")
        if got != four:
            bad.append(f"services.yaml declares the four numbers of the database "
                       f"and the generator answers {got}: the file that decides "
                       f"the image, the port and the disk does not decide this")
    except Exception as e:                               # noqa: BLE001
        bad.append(f"services.yaml declaring its four numbers is refused: {e}")
    PARTIAL = (
        ("a key with a typo (`request.memory`, no `s`)",
         dict(four, **{"request.memory": four["requests.memory"]})),
        ("three of the four numbers",
         {k: v for k, v in four.items() if k != "limits.memory"}),
        ("a number nobody can add up", dict(four, **{"limits.memory": "loads"})),
    )
    for what, block in PARTIAL:
        try:
            got = gen.platform_resources(with_recursos(block), "postgres")
        except gen.Invalid:
            continue
        except Exception as e:                           # noqa: BLE001
            bad.append(f"services.yaml with {what} does not give an Invalid: it "
                       f"BREAKS with {type(e).__name__}({e})")
            continue
        bad.append(f"services.yaml with {what} was accepted IN SILENCE and the "
                   f"database came out {got}: a field that is ignored is worse "
                   f"than one that is rejected, because whoever wrote it believes "
                   f"they sized something")

    # ── 3. the sum, and the account it shows ────────────────────────
    n = mem(quotas[smallest]) // mem(sizes[biggest]) + 2
    over = [{"nombre": f"w{i}", "tipo": "worker", "tamano": biggest}
            for i in range(1, n + 1)]
    over.append({"nombre": "datos", "tipo": "postgres"})
    try:
        gen.validate(contract(smallest, over), plans)
        bad.append(f"{n} services of tamano `{biggest}` plus a database were "
                   f"ACCEPTED against plan `{smallest}`: nothing adds the sizes "
                   f"up against the quota, so the rejection lands on the "
                   f"apiserver at deploy time, naming millicores and blaming "
                   f"whichever pod was scheduled last")
    except gen.Invalid as e:
        msg = str(e)
        # The message is the deliverable, not the boolean: an error that
        # reports a sum without its terms makes you redo by hand what
        # the machine already did.
        for want, why in (
                ("do not fit", "it does not say what went wrong"),
                ("requests.memory", "it does not name the dimension that overflowed"),
                ("w1", "it does not show the terms of the sum"),
                ("datos", "it leaves out the database — which the quota DOES "
                          "charge for, so the account would not add up"),
                (smallest, "it does not name the plan that fell short"),
                ("`cuota`", "it does not offer the way out through the plan"),
                ("`tamano`", "it does not offer the way out through the service")):
            if want not in msg:
                bad.append(f"the «does not fit» error is missing {want!r}: {why}")
    except Exception as e:                               # noqa: BLE001
        bad.append(f"the sum against the quota BROKE instead of rejecting: "
                   f"{type(e).__name__}({e})")

    # ── 4. the two objects that make it true in the cluster ─────────
    try:
        c = gen.validate(contract(largest, svcs), plans)
        objs = [d for d in yaml.safe_load_all(gen.render_bundle(c, plans, "sha256:0"))
                if isinstance(d, dict)]
    except Exception as e:                               # noqa: BLE001
        objs = []
        bad.append(f"the bundle of a contract with two sizes and a database does "
                   f"not render: {type(e).__name__}({e})")

    def numbers(block):
        """The rendered {requests,limits} as the four dotted keys."""
        return {f"{side}.{dim}": block[side][dim]
                for side in ("requests", "limits") for dim in ("cpu", "memory")}

    def same(want, got):
        """Equal AS QUANTITIES: `1` and `1000m` are the same reservation,
        and comparing the strings would make this check red on a
        rewriting that changed nothing."""
        return all((gen._cpu if k.endswith(".cpu") else gen._mem)(want[k])
                   == (gen._cpu if k.endswith(".cpu") else gen._mem)(got[k])
                   for k in gen.SIZE_KEYS)

    lrs = [d for d in objs if d.get("kind") == "LimitRange"]
    if len(lrs) != 1:
        if objs:
            bad.append(f"the bundle carries {len(lrs)} LimitRange and not 1: with "
                       f"a ResourceQuota over requests/limits, a container that "
                       f"declares no resources is REJECTED by the apiserver with a "
                       f"message that names the quota and never the Deployment "
                       f"that forgot the block")
    else:
        lim = (lrs[0]["spec"]["limits"] or [{}])[0]
        if lim.get("type") != "Container":
            bad.append(f"the LimitRange is of type {lim.get('type')!r} and not "
                       f"Container: the quota charges per container and a "
                       f"Pod-level default says nothing about a sidecar")
        want = {"requests.cpu": sizes[gen.DEFAULT_SIZE]["requests.cpu"],
                "requests.memory": sizes[gen.DEFAULT_SIZE]["requests.memory"],
                "limits.cpu": sizes[gen.DEFAULT_SIZE]["limits.cpu"],
                "limits.memory": sizes[gen.DEFAULT_SIZE]["limits.memory"]}
        got = {"requests.cpu": (lim.get("defaultRequest") or {}).get("cpu"),
               "requests.memory": (lim.get("defaultRequest") or {}).get("memory"),
               "limits.cpu": (lim.get("default") or {}).get("cpu"),
               "limits.memory": (lim.get("default") or {}).get("memory")}
        try:
            ok = same(want, got)
        except Exception:                                # noqa: BLE001
            ok = False
        if not ok:
            bad.append(f"the LimitRange does not carry the default tamano "
                       f"`{gen.DEFAULT_SIZE}` of plans.yaml: it says {got}, the "
                       f"file says {want}. The floor and the word have to agree, "
                       f"or a container that declares nothing is charged one "
                       f"figure and documented as another")

    pols = [d for d in objs if d.get("kind") == "Policy"
            and str(d.get("apiVersion", "")).startswith("kyverno.io/")]
    if len(pols) != 1:
        if objs:
            bad.append(f"the bundle carries {len(pols)} Kyverno Policy and not 1: "
                       f"without it each service's resources go back to being a "
                       f"number in the tenant's own Deployment, which is where "
                       f"50m/32Mi killed a JVM on start-up and no number was the "
                       f"platform's to choose")
    else:
        spec = pols[0].get("spec") or {}
        if (pols[0].get("metadata") or {}).get("namespace") != "org-talla":
            bad.append("the Policy is not written into the organization's "
                       "namespace: a namespaced Policy outside it governs nothing")
        if spec.get("background") is not False:
            bad.append("the Policy does not set background: false — a running "
                       "pod's resources are immutable, so a background sweep can "
                       "only report what it cannot change")
        if ((spec.get("webhookConfiguration") or {}).get("failurePolicy")
                != "Fail"):
            bad.append("the Policy does not set failurePolicy: Fail — a pod "
                       "admitted while Kyverno was down runs with the tenant "
                       "repo's numbers and is charged against this quota, which "
                       "is the state the Policy exists to end")
        rules = {r.get("name"): r for r in spec.get("rules") or []}
        if "tamano-datos" in rules:
            bad.append("the Policy carries a rule for the database: what a "
                       "provided service asks for is rendered into its own "
                       "manifest from services.yaml, and two authorities over "
                       "the same numbers is how they drift apart")
        for s in svcs[:2]:
            r = rules.get(f"tamano-{s['nombre']}")
            if r is None:
                bad.append(f"the Policy has no rule for service {s['nombre']!r}: "
                           f"its pods keep whatever its own repo asked for")
                continue
            sel = (((r.get("match") or {}).get("any") or [{}])[0]
                   .get("resources", {}).get("selector", {}).get("matchLabels", {}))
            if sel.get("app") != f"talla-{s['nombre']}":
                bad.append(f"the rule for {s['nombre']!r} selects "
                           f"{sel.get('app')!r} and the NetworkPolicies label the "
                           f"pod `talla-{s['nombre']}`: one convention, or a pod "
                           f"ends up with the network of one service and the size "
                           f"of another")
            try:
                merge = r["mutate"]["foreach"][0]["patchStrategicMerge"]
                cont = merge["spec"]["containers"][0]
                got = numbers(cont["resources"])
            except Exception as e:                       # noqa: BLE001
                bad.append(f"the rule for {s['nombre']!r} does not patch the "
                           f"containers' resources: {type(e).__name__}({e})")
                continue
            if "element.name" not in str(cont.get("name")):
                bad.append(f"the rule for {s['nombre']!r} patches container "
                           f"{cont.get('name')!r} and not the foreach element: "
                           f"container names belong to the tenant and a strategic "
                           f"merge needs the name to find its target")
            want = sizes[s.get("tamano", gen.DEFAULT_SIZE)]
            try:
                ok = same(want, got)
            except Exception:                            # noqa: BLE001
                ok = False
            if not ok:
                bad.append(f"the rule for {s['nombre']!r} fixes {got} and its "
                           f"contract asks for tamano "
                           f"`{s.get('tamano', gen.DEFAULT_SIZE)}`, which "
                           f"plans.yaml prices at {dict(want)}: the word and the "
                           f"numbers stopped being the same fact")

    # ── 5. and the tenant cannot take the pen back ──────────────────
    (tmp / "orgs" / "talla.yaml").write_text(
        yaml.safe_dump(contract(largest, svcs), sort_keys=False), encoding="utf-8")
    try:
        projects = [d for d in yaml.safe_load_all(gen.render_appprojects())
                    if isinstance(d, dict)
                    and (d.get("metadata") or {}).get("name") == "aegis-tenant-talla"]
    except Exception as e:                               # noqa: BLE001
        projects = []
        bad.append(f"the tenant's AppProject does not render: {type(e).__name__}({e})")
    if not projects:
        bad.append("no AppProject was derived for an organization that declares a "
                   "repo: the boundary this check measures does not exist")
    else:
        blocked = {(e.get("group"), e.get("kind")) for e
                   in projects[0]["spec"].get("namespaceResourceBlacklist") or []}
        for group, kind, why in (
                ("kyverno.io", "Policy",
                 "the Policy that fixes each service's size is namespaced and "
                 "lives in org-<org>, the one namespace this project may write: "
                 "without this line the tenant ships a Policy of its own, mutates "
                 "its pods back to whatever it likes, and what is left holding is "
                 "the ResourceQuota — the coarse wall `tamano` exists to refine"),
                ("", "ResourceQuota",
                 "the organization would raise its own ceiling"),
                ("", "LimitRange",
                 "the organization would rewrite the floor the platform set")):
            if (group, kind) not in blocked:
                bad.append(f"the tenant's AppProject does not blacklist "
                           f"{(group + '/') if group else ''}{kind}: {why}")

shutil.rmtree(tmp, ignore_errors=True)
print(f"    {len(sizes)} sizes in plans.yaml · {len(gen.SIZE_KEYS)} numbers each · "
      f"default `{gen.DEFAULT_SIZE}` · the sum, the LimitRange, the Kyverno "
      f"Policy and the tenant's blacklist exercised", file=sys.stderr)
for m in bad:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D149" ]]; then
    fail "the service sizes are not a vocabulary the platform can serve and enforce$D149"
else
    pass "a size is a word with four numbers behind it, the generator adds them against the quota and shows the account, the bundle carries the LimitRange and the Policy that impose them, and the tenant cannot overwrite either"
fi
}
