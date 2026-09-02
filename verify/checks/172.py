# scanner of check 172 — every .enc.yaml an organization's generator
# declares has somebody in the artifact that makes it.
#
# IT DOES NOT READ THE COMMAND, IT RUNS IT. `aegis secret` is loaded as
# a module, pointed at a synthetic platform built out of the seed's OWN
# generators, and asked to make each file. What gets measured is which
# of its two ways out it takes — invent the material, or copy it from
# the namespace that already holds it — and a file for which it takes
# neither is a file nobody creates.
#
# Running it instead of grepping it is what keeps this check off the
# prose. The paragraph in libexec/aegis-secret that explains the regcred
# names the file with exactly the words the defect would, and eight
# checks had to be corrected in one day for reading that kind of
# paragraph as code. Here a comment cannot be reached: what answers is
# the interpreter.
#
# sops is never invoked and no material is ever produced: the two
# writers (`_sops_encrypt` and `relocate`) are replaced by recorders, so
# this measures the DECISION and nothing else.
import contextlib
import importlib.machinery
import importlib.util
import io
import os
import pathlib
import shutil
import sys
import tempfile

import yaml

sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

root = pathlib.Path(sys.argv[1]).resolve()
P = root / "seed" / "platform"
ORGS_K8S = P / "k8s" / "organizations"


def declared(gen):
    """The .enc.yaml files a ksops generator lists."""
    out = []
    for doc in yaml.safe_load_all(gen.read_text(encoding="utf-8")):
        if not isinstance(doc, dict):
            continue
        for x in (doc.get("files") or []):
            if isinstance(x, str) and x.endswith(".enc.yaml"):
                out.append(x)
    return out


if not ORGS_K8S.is_dir():
    print("__NOSUBJECT__ the seed carries no k8s/organizations/")
    raise SystemExit(0)

# ── the subject, derived twice from the same truth ───────────────────
# (a) what the organization generators SHIPPED in the seed declare, and
#     (b) what `org.secrets_of` — the very function that RENDERS every
#     one of those generators — can emit. (b) is the maximal set: one
#     contract carrying one service of every type the platform provides,
#     plus ai and a bucket. Both halves come out of the artifact;
#     neither is a list somebody has to remember to update, which is how
#     three consumer lists in this repo went stale in a single day.
subject = {}          # filename -> where it was declared
for g in sorted(ORGS_K8S.rglob("secret-generator.yaml")):
    for f in declared(g):
        subject.setdefault(f, f"{g.parent.name}'s generator")

os.environ["AEGIS_ROOT"] = str(root)
sys.path.insert(0, str(root / "lib"))
try:
    from aegis import org as gen
except Exception as e:                                   # noqa: BLE001
    print(f"the product's generator could not be loaded ({e}), so the set of secrets an "
          f"organization declares cannot be derived and this check would pass green over "
          f"a tree it never read")
    raise SystemExit(0)

try:
    # The service NAMES are irrelevant to the question (the recipe for
    # `secret-<x>-credenciales.enc.yaml` keys off the suffix, not the
    # word), so the type is reused as the name and the probe stays
    # derived from PROVIDED instead of being written out by hand.
    probe = {
        "organizacion": "probe",
        "servicios": [{"nombre": t, "tipo": t} for t in sorted(gen.PROVIDED)],
        "ai": {"plan": "probe"},
        "almacenamiento": {"bucket": "probe"},
    }
    for f in gen.secrets_of(probe):
        subject.setdefault(f, "org.secrets_of, the function that renders those generators")
except Exception as e:                                   # noqa: BLE001
    print(f"org.secrets_of could not be asked what an organization declares ({e}): the shape "
          f"of a contract changed under it and this check has no subject it can trust")
    raise SystemExit(0)

# ── a synthetic platform, built out of the generators themselves ─────
# The state of a live instance the moment an organization is signed up:
# THE PLATFORM'S credentials already exist —the init wrote every one of
# them, which is what check 145 demands— and no organization's do. So
# only the generators under k8s/base materialise their files here;
# k8s/organizations/ starts empty, because that is the only assumption
# an organization created after the init is allowed to make.
#
# Materialising the organizations' too would have been the comfortable
# mistake: the canary declares the same regcred, so every organization
# would appear to have an origin to copy from and this check would go
# green over a platform that has none. Nothing is read out of these
# files —`relocate` is a recorder here— so their content is only a note
# to whoever finds one.
tmp = pathlib.Path(tempfile.mkdtemp(prefix="aegis-172."))
try:
    for g in sorted((P / "k8s" / "base").rglob("secret-generator.yaml")):
        d = tmp / g.parent.relative_to(P)
        d.mkdir(parents=True, exist_ok=True)
        for f in declared(g):
            (d / f).write_text("# stand-in for encrypted material (check 172)\n")
    for extra in ("plans.yaml", "services.yaml", "edge.yaml"):
        if (P / extra).is_file():
            shutil.copy2(P / extra, tmp / extra)

    # The organization under test is a NEW one: its directory is empty,
    # exactly as `aegis org apply` leaves it before any secret exists.
    orgdir = tmp / "k8s" / "organizations" / "org-probe"
    orgdir.mkdir(parents=True, exist_ok=True)

    os.environ["PLATFORM_DIR"] = str(tmp)
    loader = importlib.machinery.SourceFileLoader(
        "aegis_secret_under_test", str(root / "libexec" / "aegis-secret"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    try:
        loader.exec_module(mod)
    except Exception as e:                               # noqa: BLE001
        print(f"libexec/aegis-secret could not be loaded ({e}): the command that creates an "
              f"organization's secrets does not even import, so nothing creates them")
        raise SystemExit(0)

    took = []
    mod._sops_encrypt = lambda target, document: took.append(("invents", target))
    mod.relocate = lambda source, target: (took.append(("copies", source)), 0)[1]
    mod._deploy_key = lambda comment: ("(not generated)", "(not generated)")

    ways = {}
    for f in sorted(subject):
        took.clear()
        target = orgdir / f
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                mod.create(str(target))
        except Exception as e:                           # noqa: BLE001
            print(f"{f} is declared by {subject[f]} and `aegis secret create` blows up on it "
                  f"({type(e).__name__}: {e}) — an organization whose contract asks for it "
                  f"cannot be signed up")
            continue
        if not took:
            print(f"{f} is declared by {subject[f]} and `aegis secret create` makes it neither "
                  f"way: it has no recipe and the command derives no origin for it, so the "
                  f"file is never written. The ksops generator lists it all the same, so "
                  f"`kustomize build` of the whole organization dies with «no such file or "
                  f"directory», the Application never renders, and ArgoCD reports nothing "
                  f"unhealthy because nothing was ever created")
            continue
        ways[f] = took[0][0]

    invented = sum(1 for w in ways.values() if w == "invents")
    copied = sum(1 for w in ways.values() if w == "copies")
    print(f"__COUNT__ {len(subject)} {invented} {copied}", file=sys.stderr)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
