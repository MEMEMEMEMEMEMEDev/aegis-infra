"""Check 121 — a silent apiserver is not an empty organization.

The thesis of the product, applied to the screen a person will spend
the most time on. `aegis tenant show` answers «what does this
organization actually have running», and there are three answers that
look alike on a page and mean opposite things:

  · seven services, all running        nothing to do
  · seven services, none running       the namespace is gone: act now
  · nobody could ask                   the instrument never arrived

The dangerous confusion is the last two. A console that drew seven
absent services because kubectl could not reach anything would have
the operator rebuilding an organization that was serving traffic the
whole time — and every number on the screen would be true of the
document in front of them.

So this exercises the real command three ways against a fixture tree
and demands the three come out different: blind is rc 2 and names NO
service, an absent namespace is rc 1 and names EVERY service, and a
healthy one is rc 0.
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
CMD = os.path.join(ROOT, "libexec", "aegis-tenant")

if not os.path.isfile(CMD):
    print("SCOPE: there is no `aegis tenant`: this check has no subject")
    sys.exit(0)

# The stub is the instrument under test's own instrument: the command
# shells out to kubectl, so a kubectl that answers from a script is the
# only way to put a cluster in front of it inside `aegis verify`.
STUB = r'''#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
scene = json.load(open(os.environ["STUB_SCENE"]))
if scene.get("silent"):
    sys.stderr.write("The connection to the server localhost:8080 was refused\n")
    sys.exit(1)
if argv[:2] == ["get", "namespace"]:
    if not scene.get("namespace", True):
        sys.stderr.write('Error from server (NotFound): namespaces "x" not found\n')
        sys.exit(1)
    print(json.dumps({"status": {"phase": "Active"}}))
    sys.exit(0)
kind = argv[argv.index("get") + 1] if "get" in argv else ""
print(json.dumps({"items": scene.get(kind, [])}))
'''


def workload(kind, name, app, ready=1, desired=1):
    return {"kind": kind, "metadata": {"name": name, "labels": {"app": app}},
            "spec": {"replicas": desired, "template": {"spec": {"containers": [
                {"image": f"registry.example.test/{name}@sha256:" + "a" * 64}]}}},
            "status": {"readyReplicas": ready}}


def run(home, scene):
    scene_file = os.path.join(home, "scene.json")
    with open(scene_file, "w", encoding="utf-8") as fh:
        json.dump(scene, fh)
    env = {k: v for k, v in os.environ.items()
           if not (k.startswith("AEGIS_") or k == "PLATFORM_DIR")}
    env.update({"AEGIS_HOME": home, "AEGIS_ROOT": ROOT, "STUB_SCENE": scene_file,
                "PATH": os.path.join(home, "bin") + os.pathsep + env.get("PATH", "")})
    r = subprocess.run([os.path.join(ROOT, "bin", "aegis"), "tenant", "show",
                        "unaorg", "--json"],
                       capture_output=True, text=True, env=env, cwd=home)
    try:
        return r.returncode, json.loads(r.stdout)
    except ValueError:
        return r.returncode, None


home = tempfile.mkdtemp(prefix="aegis-121-")
try:
    shutil.copytree(os.path.join(ROOT, "seed", "platform"), os.path.join(home, "platform"))
    with open(os.path.join(home, "platform", "orgs", "unaorg.yaml"), "w",
              encoding="utf-8") as fh:
        fh.write("version: 1\norganizacion: unaorg\ndominio: unaorg.example.test\n"
                 "cuota: pequena\nservicios:\n"
                 "  - nombre: web\n    tipo: estatico\n    publico: /\n"
                 "    repo: git@github.com:owner/unaorg-web.git\n"
                 "  - {nombre: datos, tipo: postgres}\n")
    os.mkdir(os.path.join(home, "bin"))
    stub = os.path.join(home, "bin", "kubectl")
    with open(stub, "w", encoding="utf-8") as fh:
        fh.write(STUB)
    os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    healthy = {"deployment": [workload("Deployment", "unaorg-web", "unaorg-web")],
               "statefulset": [workload("StatefulSet", "datos", "unaorg-datos")],
               "persistentvolumeclaim": [{"metadata": {"name": "datos-datos-0",
                                                       "labels": {"app": "unaorg-datos"}},
                                          "status": {"phase": "Bound",
                                                     "capacity": {"storage": "2Gi"}}}],
               "endpoints": [{"metadata": {"name": "unaorg-web"},
                              "subsets": [{"addresses": [{"ip": "10.0.0.1"}]}]}],
               "ingressroute.traefik.io": [{"spec": {"routes": [
                   {"match": "Host(`unaorg.example.test`)",
                    "services": [{"name": "unaorg-web"}]}]}}],
               "resourcequota": [{"metadata": {"name": "unaorg-quota"},
                                  "status": {"used": {"pods": "2"}, "hard": {"pods": "40"}}}]}

    findings = []

    rc_blind, blind = run(home, {"silent": True})
    if blind is None:
        findings.append(f"with a silent apiserver the command returned no document "
                        f"(rc {rc_blind}): the screen has nothing to draw and no reason")
    else:
        steps = blind.get("steps") or []
        named = [s.get("step", "") for s in steps]
        if blind.get("rc") != 2:
            findings.append(f"a silent apiserver reports rc {blind.get('rc')}, not 2: "
                            f"«I could not look» is being filed as a measurement")
        if not any(s.get("state") == "not-evaluable" for s in steps):
            findings.append("a silent apiserver produces no `not-evaluable` step: the one "
                            "state that says nobody asked is missing")
        drawn = [n for n in named if n.startswith("service:")]
        if drawn:
            findings.append(f"a silent apiserver still draws {len(drawn)} service(s) "
                            f"({', '.join(drawn[:3])}): an organization nobody could look "
                            f"at is being reported as an organization with nothing running, "
                            f"and those two ask for opposite decisions")

    rc_gone, gone = run(home, dict(healthy, namespace=False))
    if gone is None:
        findings.append(f"with the namespace absent the command returned no document (rc {rc_gone})")
    else:
        steps = gone.get("steps") or []
        named = {s.get("step", ""): s for s in steps}
        if gone.get("rc") != 1:
            findings.append(f"an absent namespace reports rc {gone.get('rc')}, not 1: the "
                            f"apiserver ANSWERED, and what it answered is that nothing is there")
        if any(s.get("state") == "not-evaluable" for s in steps):
            findings.append("an absent namespace produces a `not-evaluable` step: a measured "
                            "absence is being reported as a failure to measure")
        missing = [n for n in named if n.startswith("service:")]
        if len(missing) != 2:
            findings.append(f"an absent namespace names {len(missing)} of the 2 declared "
                            f"services: the screen cannot show the shape of what is missing")

    rc_ok, ok = run(home, healthy)
    if ok is None:
        findings.append(f"a healthy organization returned no document (rc {rc_ok})")
    elif ok.get("rc") != 0:
        wrong = [s.get("step") for s in ok.get("steps") or []
                 if s.get("state") in ("wrong", "not-evaluable")]
        findings.append(f"a healthy organization reports rc {ok.get('rc')}: {wrong} — the "
                        f"three answers stop being distinguishable if the good one is not green")

    for f in findings:
        print(f)
    print(f"SCOPE: 3 exercises against a stub apiserver — blind rc "
          f"{(blind or {}).get('rc')}, namespace absent rc {(gone or {}).get('rc')}, "
          f"healthy rc {(ok or {}).get('rc')}")
finally:
    shutil.rmtree(home, ignore_errors=True)
