# title: plans.yaml declares the three service sizes with their four numbers, and the generator rejects one it does not know
# origin: new in v3 — 2026-08-29, a service's resources lived in the tenant's repo: 50m/32Mi for everything, and that kills a JVM on start-up
check() {
# WHAT THIS PROTECTS. A contract says `tamano: mediano` and names no
# number; the numbers live in plans.yaml. That inversion only holds
# while the words on both sides are the same words. If a size
# disappears from plans.yaml —renamed, tidied away, lost in a merge—
# every contract that asks for it STOPS VALIDATING, and the contracts
# do not live in this repo: they live in each instance, so nothing in
# this tree would turn red. The seed would ship a vocabulary its own
# instances cannot speak.
#
# And a half-written size is worse than a missing one: a step with
# `requests` and no `limits` renders a LimitRange and an admission
# patch with a hole in them, and a container with no ceiling is exactly
# what the quota exists to prevent.
#
# WHAT IS DERIVED AND WHAT IS TYPED, because the difference is the
# check's own honesty:
#   derived from lib/aegis/org.py  the four keys a size is made of
#                                  (SIZE_KEYS) and the default a
#                                  contract gets when it names none
#                                  (DEFAULT_SIZE)
#   typed here                     the three names. They are contract
#                                  VOCABULARY —a word somebody may
#                                  write in a file this repo will never
#                                  see— and there is nowhere else to
#                                  read them from that would not be the
#                                  very file under test.
#
# The second half measures the other direction: the generator has to
# REJECT a size plans.yaml does not carry. A validator that accepts an
# invented word writes a manifest with no resources at all and the
# failure lands on the apiserver, hours later, naming millicores.
D149=""
python3 - "$AEGIS_ROOT" "$P" <<'PY' || D149=" (see the detail above)"
import os, pathlib, sys

root, P = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
# The generator resolves the instance at import time. It is pointed at
# the seed and only `validate` is called, which writes nothing.
os.environ.setdefault("PLATFORM_DIR", str(P))
sys.path.insert(0, str(root / "lib"))
try:
    import yaml
    from aegis import org as gen
except Exception as e:                                   # noqa: BLE001
    print(f"    the product's generator does not load: {e}", file=sys.stderr)
    sys.exit(1)

DOCUMENTED = ("chico", "mediano", "grande")

bad = []
plans = yaml.safe_load((P / "plans.yaml").read_text(encoding="utf-8")) or {}
sizes = plans.get("tamano") or {}

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

# ── the other direction: an invented size has to be REJECTED ─────────
CONTRACT = """
version: 1
organizacion: talla
dominio: talla.__ROOT_DOMAIN__
cuota: %s
repo: git@github.com:owner/repo.git
servicios:
  - {nombre: front, tipo: estatico, publico: /, tamano: %s}
"""
quota = sorted(plans.get("cuota") or {})
if not quota:
    bad.append("plans.yaml declares no quota plan: the rejection could not be exercised")
else:
    invented = "no-such-size"
    while invented in sizes:
        invented += "x"
    try:
        gen.validate(yaml.safe_load(CONTRACT % (quota[0], invented)), plans)
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
    # everything would come out green on the line above
    if gen.DEFAULT_SIZE in sizes:
        try:
            gen.validate(yaml.safe_load(CONTRACT % (quota[0], gen.DEFAULT_SIZE)), plans)
        except Exception as e:                           # noqa: BLE001
            bad.append(f"the generator rejects `tamano: {gen.DEFAULT_SIZE}`, which "
                       f"plans.yaml DOES carry: {str(e).splitlines()[0]}")

print(f"    {len(sizes)} sizes in plans.yaml · {len(gen.SIZE_KEYS)} numbers each · "
      f"default `{gen.DEFAULT_SIZE}`", file=sys.stderr)
for m in bad:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D149" ]]; then
    fail "the service sizes are not a vocabulary the generator can serve$D149"
else
    pass "the three sizes are declared with their four numbers, and the generator rejects a size plans.yaml does not carry"
fi
}
