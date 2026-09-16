"""Check 204 — a plan of your own is a named step, validated like the
shipped ones, and the shipped ones keep their numbers.

`aegis quota` is the one command that writes plans.yaml, and plans.yaml
is the file every contract's ceiling comes from. So it is exercised for
real, on a copy of the seed's platform in tmpfs, and the FILE is what is
asserted on: a plan added is a plan the validator accepts in a contract;
added and removed leaves the file byte-identical; the numbers a shipped
plan carries cannot be changed; a plan a contract names cannot go; a
ceiling under its floor is not a plan. Nothing here touches the instance.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
SEED = os.path.join(ROOT, "seed", "platform")
AEGIS = os.path.join(ROOT, "bin", "aegis")
findings = []

if not os.path.isdir(SEED) or not os.path.isfile(os.path.join(ROOT, "libexec", "aegis-quota")):
    print("SCOPE: there is no seed platform or no `aegis quota`: nothing to exercise")
    sys.exit(0)

home = tempfile.mkdtemp(prefix="aegis-204-")
try:
    shutil.copytree(SEED, os.path.join(home, "platform"))
    plans = os.path.join(home, "platform", "plans.yaml")
    orgs = os.path.join(home, "platform", "orgs")
    env = {k: v for k, v in os.environ.items()
           if not (k.startswith("AEGIS_") or k == "PLATFORM_DIR")}
    env["AEGIS_HOME"] = home
    env["AEGIS_ROOT"] = ROOT

    def quota(*args):
        run = subprocess.run([AEGIS, "quota", *args, "--json"], capture_output=True,
                             text=True, env=env, cwd=home)
        try:
            doc = json.loads(run.stdout)
        except ValueError:
            return None, run
        return doc, run

    def step(doc, name):
        return next((s for s in (doc or {}).get("steps") or [] if s.get("step") == name), {})

    def text():
        return open(plans, encoding="utf-8").read()

    before = text()
    # ── listed, and the shipped ones say so ──
    doc, run = quota("list")
    if doc is None:
        print(f"`aegis quota list --json` returned no document (rc {run.returncode}): "
              f"{(run.stderr or run.stdout)[:160]!r}")
        print("SCOPE: the catalogue could not be listed")
        sys.exit(0)
    listed = {s["step"].split(":", 1)[1]: s for s in doc["steps"] if s["step"].startswith("plan:")}
    if not listed:
        findings.append("the seed's catalogue lists no plan")
    if not all(s.get("de_serie") for s in listed.values()):
        findings.append("a plan of the seed is not listed as shipped: the numbers that stay "
                        "are the ones nobody can tell apart")
    base = "mediana" if "mediana" in listed else (sorted(listed)[0] if listed else "")

    # ── added, then removed: the file comes back byte-identical ──
    doc, run = quota("add", "trial", "--from", base, "--set", "requests.memory=8Gi",
                     "--set", "limits.memory=16Gi", "--describe", "A trial plan.")
    if step(doc, "plan:trial").get("state") != "done":
        findings.append(f"adding a plan from {base!r} was not done: "
                        f"{step(doc, 'plan:trial').get('error') or run.stderr[:160]!r}")
    if before.count("#") > text().count("#"):
        findings.append("adding a plan lost comment lines of plans.yaml: the file is argued "
                        "in its margins and a write that erases them erases the argument")
    doc, _ = quota("list")
    trial = step(doc, "plan:trial")
    if trial.get("de_serie") is not False or (trial.get("numeros") or {}).get("requests.memory") != "8Gi":
        findings.append("the plan added is not listed as yours with the numbers it was given")
    # a contract may name it: the generator accepts what the command wrote
    contract = os.path.join(home, "c.yaml")
    with open(contract, "w", encoding="utf-8") as fh:
        fh.write("version: 1\norganizacion: prueba\ndominio: prueba.example.test\n"
                 "cuota: trial\nservicios:\n  - nombre: web\n    tipo: estatico\n"
                 "    publico: /\n    repo: git@github.com:owner/prueba.git\n")
    run = subprocess.run([AEGIS, "org", "validate", contract, "--json"], capture_output=True,
                         text=True, env=env, cwd=home)
    try:
        vdoc = json.loads(run.stdout)
    except ValueError:
        vdoc = {"rc": None}
    if vdoc.get("rc") != 0:
        findings.append("a contract naming the plan just added does not validate: the "
                        "command wrote a plan the generator refuses")
    doc, _ = quota("add", "trial", "--from", base)
    if step(doc, "plan:trial").get("state") != "wrong":
        findings.append("adding a plan whose name exists was not refused")
    doc, _ = quota("remove", "trial")
    if step(doc, "plan:trial").get("state") != "done":
        findings.append("removing a plan of your own that no contract names was not done")
    if text() != before:
        findings.append("adding and removing a plan did not leave plans.yaml byte-identical: "
                        "the write leaves something behind")

    # ── the shipped ones keep their numbers; their sentence may change ──
    doc, _ = quota("set", base, "--set", "pods=1")
    if step(doc, f"plan:{base}").get("state") != "wrong":
        findings.append(f"the numbers of the shipped plan {base!r} could be changed")
    doc, _ = quota("set", base, "--describe", "Reworded.")
    if step(doc, f"plan:{base}").get("state") != "done":
        findings.append(f"the sentence of the shipped plan {base!r} could not be set")
    doc, _ = quota("remove", base)
    if step(doc, f"plan:{base}").get("state") != "wrong":
        findings.append(f"the shipped plan {base!r} could be removed")

    # ── a plan a contract names stays ──
    quota("add", "used", "--from", base)
    with open(os.path.join(orgs, "usa-used.yaml"), "w", encoding="utf-8") as fh:
        fh.write("version: 1\norganizacion: usaused\ndominio: u.example.test\ncuota: used\n"
                 "servicios:\n  - nombre: web\n    tipo: estatico\n    publico: /\n"
                 "    repo: git@github.com:owner/u.git\n")
    doc, _ = quota("remove", "used")
    if step(doc, "plan:used").get("state") != "wrong":
        findings.append("a plan a contract names could be removed: that contract stops "
                        "validating the moment it is gone")
    os.remove(os.path.join(orgs, "usa-used.yaml"))
    quota("remove", "used")

    # ── what is not a plan ──
    for args, what in ((("other", "--from", base, "--set", "limits.cpu=1"),
                        "a CPU ceiling under the floor"),
                       (("other", "--from", base, "--set", "foo=1"),
                        "a key that is not one of the seven"),
                       (("other", "--from", "nosuch"), "a base that does not exist"),
                       (("Bad-Name", "--from", base), "a name the contract could not carry"),
                       (("other", "--from", base, "--set", "pods=abc"),
                        "a pod count that is not a number")):
        doc, _ = quota("add", *args)
        name = args[0]
        if step(doc, f"plan:{name}").get("state") != "wrong":
            findings.append(f"{what} was accepted as a plan")
        if name in {s["step"].split(":", 1)[1] for s in (quota("list")[0] or {}).get("steps") or []}:
            findings.append(f"{what} was written into plans.yaml")
finally:
    shutil.rmtree(home, ignore_errors=True)

for f in findings:
    print(f)
print("SCOPE: one plan added, named by a contract, and removed on a copy of the seed; "
      "a shipped plan's numbers, a used plan's removal and five malformed plans refused")
