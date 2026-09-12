"""Check 129 — the organizations list shows every contract, valid or not.

The worst shape this command could take is a silent filter: an
organization that exists in git, has a namespace, serves traffic — and
is not on the screen because its contract stopped validating. Nobody
would notice, because the list would look tidy.

So the check runs the real command against a tree with a BROKEN contract
in it and demands that the broken one be listed, named, and marked as
what it is. Behavioural, on a copy in tmpfs, touching nothing.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
SEED_ORGS = os.path.join(ROOT, "seed", "platform", "orgs")

if not os.path.isdir(SEED_ORGS):
    print(f"SCOPE: {os.path.relpath(SEED_ORGS, ROOT)} does not exist — the list could not be exercised")
    sys.exit(0)

home = tempfile.mkdtemp(prefix="aegis-129-")
try:
    shutil.copytree(os.path.join(ROOT, "seed", "platform"), os.path.join(home, "platform"))
    orgs = os.path.join(home, "platform", "orgs")
    # THE FIXTURE: one contract that validates and one that does not.
    # The seed's own contracts carry placeholders, so a valid one is
    # written here rather than assumed.
    with open(os.path.join(orgs, "buena.yaml"), "w", encoding="utf-8") as fh:
        fh.write("version: 1\norganizacion: buena\ndominio: buena.example.test\n"
                 "cuota: pequena\nservicios:\n  - nombre: web\n    tipo: estatico\n"
                 "    publico: /\n    repo: git@github.com:owner/buena-web.git\n")
    with open(os.path.join(orgs, "rota.yaml"), "w", encoding="utf-8") as fh:
        fh.write("version: 1\norganizacion: Rota-Mal\ndominio: rota.example.test\n"
                 "cuota: inventada\nservicios: []\n")

    # EVERY POINTER AT AN INSTANCE IS CLEARED, not just AEGIS_HOME.
    # verify/lib.sh sources lib/paths.sh, which exports PLATFORM_DIR
    # among others, and those win over AEGIS_HOME — so the first version
    # of this check ran against the REAL instance and reported its three
    # healthy contracts as proof that a broken one is listed. It was
    # measuring something true about the wrong subject, which is the
    # failure mode the register filed on 2026-09-10.
    env = {k: v for k, v in os.environ.items()
           if not (k.startswith("AEGIS_") or k == "PLATFORM_DIR")}
    env["AEGIS_HOME"] = home
    env["AEGIS_ROOT"] = ROOT
    run = subprocess.run([os.path.join(ROOT, "bin", "aegis"), "org", "list", "--json"],
                         capture_output=True, text=True, env=env, cwd=home)
    try:
        doc = json.loads(run.stdout)
    except ValueError:
        print(f"`aegis org list --json` did not return a readable document "
              f"(rc {run.returncode}): {(run.stdout or run.stderr)[:160]!r}")
        sys.exit(0)

    steps = doc.get("steps") or []
    named = {s.get("step", "") for s in steps}
    if not any("buena" in n for n in named):
        print("the list drops a contract that DOES validate: an organization that exists "
              "and is not on the screen")
    broken = [s for s in steps if "rota" in s.get("step", "").lower()]
    if not broken:
        print("the list drops a contract that does NOT validate: an organization can exist "
              "in git, hold a namespace and serve traffic while the screen shows a tidy "
              "list without it — which is the silent filter this command must never be")
    else:
        b = broken[0]
        if b.get("valid") is not False:
            print(f"the broken contract is listed as valid={b.get('valid')!r}: it is shown "
                  f"and it is not marked, which is worse than hiding it")
        if not (b.get("error") or "").strip():
            print("the broken contract is listed without the validator's message: the screen "
                  "says something is wrong and not what")
    if doc.get("rc") == 0:
        print(f"a contract does not validate and the document reports rc {doc.get('rc')}: "
              f"the list says everything is in order")

    print(f"SCOPE: {len(steps)} organization(s) listed from a tree with one broken contract, "
          f"rc {doc.get('rc')}")
finally:
    shutil.rmtree(home, ignore_errors=True)
