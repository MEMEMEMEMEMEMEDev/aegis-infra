"""Check 206 — every class of pin is inventoried, derived from the tree.

`aegis update` exists to answer one question: what of everything this
platform pins is behind. An inventory that quietly stops seeing a class
answers it with a number that looks right and is not — and the operator
reads «nothing to update» about thirteen charts nobody measured.

So the check derives the tree ITSELF, with its own greps and no shared
code, and demands the command name every pin it finds, with the file
and the line. Two independent readings of the same artifact: when they
disagree, one of them is broken and the run says which.
"""
import json
import os
import re
import subprocess
import sys

ROOT = sys.argv[1]
SEED = os.path.join(ROOT, "seed", "platform")
findings = []

if not os.path.isdir(SEED) or not os.path.isfile(os.path.join(ROOT, "libexec", "aegis-update")):
    print("SCOPE: there is no seed platform or no `aegis update`: nothing to inventory")
    sys.exit(0)


def walk(sub, pattern, name_of):
    """My own reading of the tree: a set of (class-agnostic) names."""
    out = set()
    base = os.path.join(SEED, sub) if sub else SEED
    for dirpath, _dirs, files in os.walk(base):
        for f in files:
            p = os.path.join(dirpath, f)
            if not pattern(f):
                continue
            try:
                text = open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            for n in name_of(text):
                out.add(n)
    return out


def _ref_name(ref):
    if "@" in ref:
        ref = ref.split("@", 1)[0]
    slash, colon = ref.rfind("/"), ref.rfind(":")
    return ref[:colon] if colon > slash else ref


INTERNAL = "registry.registry-system.svc.cluster.local:5000/"


def images_in(text, want_internal=False):
    out = []
    # the value has to be on the SAME line: a bare `image:` opens a
    # block and `\s*` would walk into the key under it.
    for m in re.finditer(r"^[^\S\n]*(?:-[^\S\n]+)?image:[^\S\n]*['\"]?([^'\"\s#]+)", text, re.M):
        ref = m.group(1)
        if "__" in ref or "$" in ref:
            continue
        if (INTERNAL in ref) != want_internal:
            continue
        slash, colon = ref.rfind("/"), ref.rfind(":")
        if colon <= slash and "@" not in ref:
            continue
        out.append(_ref_name(ref))
    return out


mine = {
    "chart": walk("k8s/argocd-apps", lambda f: f.endswith(".yaml"),
                  lambda t: [m.group(1) for m in re.finditer(r"^\s*chart:\s*(\S+)", t, re.M)]),
    "raw-image": walk("k8s", lambda f: f.endswith(".yaml"), lambda t: images_in(t)) -
                 walk("k8s/argocd-apps", lambda f: f.endswith(".yaml"), lambda t: images_in(t)),
    "jenkinsfile": walk("", lambda f: f.startswith("Jenkinsfile"),
                        lambda t: images_in(t) + images_in(t, True)),
    "mirror": walk("mirror-images", lambda f: f == "images.txt",
                   lambda t: [_ref_name(ln.split()[0]) for ln in t.splitlines()
                              if ln.strip() and not ln.startswith("#")]),
    "containerfile": walk("base-images", lambda f: f == "Containerfile",
                          lambda t: [_ref_name(m.group(1)) for m in
                                     re.finditer(r"^\s*FROM\s+(\S+)", t, re.M | re.I)
                                     if INTERNAL not in m.group(1) and "$" not in m.group(1)]) |
                     walk("ci-images", lambda f: f == "Containerfile",
                          lambda t: [_ref_name(m.group(1)) for m in
                                     re.finditer(r"^\s*FROM\s+(\S+)", t, re.M | re.I)
                                     if INTERNAL not in m.group(1) and "$" not in m.group(1)]),
}

env = {k: v for k, v in os.environ.items() if not (k.startswith("AEGIS_") or k == "PLATFORM_DIR")}
env["AEGIS_ROOT"] = ROOT
run = subprocess.run([os.path.join(ROOT, "bin", "aegis"), "update", "inventory",
                      "--tree", ROOT, "--offline", "--json"],
                     capture_output=True, text=True, env=env, cwd=ROOT)
try:
    doc = json.loads(run.stdout)
except ValueError:
    print(f"`aegis update inventory --offline --json` returned no document (rc {run.returncode}): "
          f"{(run.stdout or run.stderr)[:200]!r}")
    print("SCOPE: the inventory could not be read")
    sys.exit(0)

said = {}
for st in doc.get("steps") or []:
    if not st.get("step", "").startswith("pin:"):
        continue
    said.setdefault(st.get("clase"), set()).add(st.get("nombre"))
    if not st.get("donde"):
        findings.append(f"the pin {st.get('step')} is reported with no file and no line: an "
                        f"inventory that cannot say where a version is written cannot bump it")

# The classes the doctrine names. A class with zero pins is not «this
# tree has none»: every one of them exists in the seed, so an empty one
# is a reader that broke.
for cls in ("chart", "raw-image", "jenkinsfile", "mirror", "containerfile", "k3s", "userland"):
    if not said.get(cls):
        findings.append(f"the inventory names no pin of class {cls!r}: the derivation of that "
                        f"class is broken, and the command would report «nothing to update» "
                        f"about every one of them")

for cls, names in mine.items():
    missing = sorted(n for n in names if n not in (said.get(cls) or set())
                     # charts are keyed by their Application, so the check
                     # compares the chart names it found against what the
                     # inventory carries as data, not as a name.
                     and cls != "chart")
    if cls == "chart":
        charts_said = {st.get("chart") for st in doc.get("steps") or []
                       if st.get("clase") == "chart"}
        missing = sorted(n for n in names if n not in charts_said)
    if missing:
        findings.append(f"{cls}: the tree pins {missing} and the inventory does not name "
                        f"{'them' if len(missing) > 1 else 'it'}")

for f in findings:
    print(f)
print(f"SCOPE: {sum(len(v) for v in mine.values())} pin(s) found by this check's own reading "
      f"against {sum(len(v) for v in said.values())} the command reports, "
      f"{len(said)} class(es)")
