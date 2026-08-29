# title: a service's size is a word with four numbers behind it, and neither plans.yaml nor services.yaml gets to be half written
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
# WHAT IS DERIVED AND WHAT IS TYPED, because the difference is the
# check's own honesty:
#   derived from lib/aegis/org.py  the four keys a size is made of
#                                  (SIZE_KEYS), the default a contract
#                                  gets when it names none
#                                  (DEFAULT_SIZE), and the table of
#                                  what a provided service asks for
#   derived from plans.yaml        which plan gives least, so the
#                                  contract that must go through is
#                                  built from the file's own arithmetic
#                                  and not from numbers typed here,
#                                  which would rot the first time a plan
#                                  is re-tuned
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
    print("    plans.yaml does not hold together: the rejections were not "
          "exercised", file=sys.stderr)
else:
    # Derived, never typed: the plan that gives least is what makes the
    # positive case real —the largest one would never be tight— and a
    # number typed here would rot the first time a plan is re-tuned.
    smallest = min(quotas, key=lambda q: mem(quotas[q]))

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

shutil.rmtree(tmp, ignore_errors=True)
print(f"    {len(sizes)} sizes in plans.yaml · {len(gen.SIZE_KEYS)} numbers each · "
      f"default `{gen.DEFAULT_SIZE}` · a partial plans.yaml and a partial "
      f"services.yaml both rejected", file=sys.stderr)
for m in bad:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D149" ]]; then
    fail "the service sizes are not a vocabulary the generator can serve$D149"
else
    pass "a size is a word with four numbers behind it, and a plans.yaml or a services.yaml with a hole in it is refused by name instead of surfacing as a traceback"
fi
}
