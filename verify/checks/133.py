"""Check 133 — nothing inside a tenant's namespace goes unnamed.

MEASURED THE FIRST TIME the command ran against a real instance. An
organization whose contract declares one stateless service was holding
a hundred gigabytes on a bound claim that came out of its own repo.
Nothing about it looked wrong: the claim was Bound, the pod Running,
ArgoCD Synced, the round green. And `aegis data` had never heard of it,
because `aegis data` reads CONTRACTS — so a hundred gigabytes had no
copy and nothing on the machine said so.

That is the shape of the whole class: the contract is what every tool
here derives from, so anything in the namespace the contract does not
name is invisible to every tool at once. The one place it can be caught
is the command that looks at the namespace itself, and only if it
refuses to walk past what it does not recognise.

So the exercise puts a workload and a claim into the namespace that no
service declares, and demands both be NAMED and counted as findings.
A screen may draw them quietly at the bottom; what it may not do is not
know about them.
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

STUB = r'''#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
scene = json.load(open(os.environ["STUB_SCENE"]))
if argv[:2] == ["get", "namespace"]:
    print(json.dumps({"status": {"phase": "Active"}}))
    sys.exit(0)
kind = argv[argv.index("get") + 1] if "get" in argv else ""
print(json.dumps({"items": scene.get(kind, [])}))
'''


def workload(kind, name, app):
    return {"kind": kind, "metadata": {"name": name, "labels": {"app": app}},
            "spec": {"replicas": 1, "template": {"spec": {"containers": [
                {"image": f"registry.example.test/{name}@sha256:" + "a" * 64}]}}},
            "status": {"readyReplicas": 1}}


def claim(name, app, size):
    meta = {"name": name}
    if app:
        meta["labels"] = {"app": app}
    return {"metadata": meta,
            "status": {"phase": "Bound", "capacity": {"storage": size}}}


home = tempfile.mkdtemp(prefix="aegis-133-")
try:
    shutil.copytree(os.path.join(ROOT, "seed", "platform"), os.path.join(home, "platform"))
    with open(os.path.join(home, "platform", "orgs", "unaorg.yaml"), "w",
              encoding="utf-8") as fh:
        # ONE service, stateless, public. Everything else the scene
        # carries is, by the contract, not supposed to be there.
        fh.write("version: 1\norganizacion: unaorg\ndominio: unaorg.example.test\n"
                 "cuota: pequena\nservicios:\n"
                 "  - nombre: web\n    tipo: estatico\n    publico: /\n"
                 "    repo: git@github.com:owner/unaorg-web.git\n")
    os.mkdir(os.path.join(home, "bin"))
    stub = os.path.join(home, "bin", "kubectl")
    with open(stub, "w", encoding="utf-8") as fh:
        fh.write(STUB)
    os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    scene = {
        "deployment": [workload("Deployment", "unaorg-web", "unaorg-web"),
                       # THE STRANGER: a workload nobody declared.
                       workload("Deployment", "unaorg-vieja", "unaorg-vieja")],
        "statefulset": [],
        # THE HUNDRED GIGABYTES: a bound claim with no service behind it.
        # One carries an `app` label that matches nothing and the other
        # carries none at all, because the real one had none — and a
        # sweep that only looks at labelled claims walks past exactly
        # the case that produced this check.
        "persistentvolumeclaim": [claim("unaorg-datos", None, "100Gi"),
                                  claim("unaorg-cache", "unaorg-vieja", "5Gi")],
        "endpoints": [{"metadata": {"name": "unaorg-web"},
                       "subsets": [{"addresses": [{"ip": "10.0.0.1"}]}]}],
        "ingressroute.traefik.io": [{"spec": {"routes": [
            {"match": "Host(`unaorg.example.test`)",
             "services": [{"name": "unaorg-web"}]}]}}],
        "resourcequota": [{"metadata": {"name": "unaorg-quota"},
                           "status": {"used": {"pods": "2"}, "hard": {"pods": "40"}}}],
    }
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
        doc = json.loads(r.stdout)
    except ValueError:
        print(f"`aegis tenant show --json` returned no document (rc {r.returncode}): "
              f"{(r.stdout or r.stderr)[:160]!r}")
        sys.exit(0)

    steps = doc.get("steps") or []
    findings = []
    # ON THE STEP NAMES, never on a dump of the document. The first
    # version of this check searched the whole JSON for the stranger's
    # name and passed while the stranger went unnamed, because the name
    # also happened to be the `app` label of one of the claims. A
    # measurement that is true of the text and false about the subject
    # is the failure this repo filed on 2026-09-10, in miniature.
    named = {s.get("step", "") for s in steps}

    if "unclaimed:unaorg-vieja" not in named:
        findings.append("a Deployment running in the namespace that no service of the "
                        "contract claims is not named as unclaimed: it is invisible to "
                        "every tool here at once, because every tool here derives from "
                        "the contract")
    if "unclaimed-volume:unaorg-datos" not in named:
        findings.append("a BOUND 100Gi claim that no service of the contract declares is "
                        "not named as unclaimed — which is the exact state measured on a "
                        "live instance on 2026-09-12: a hundred gigabytes with no copy, "
                        "and nothing on the machine saying so")
    if "unclaimed-volume:unaorg-cache" not in named:
        findings.append("a bound claim whose `app` label matches no service is not named: "
                        "a sweep that trusts the label walks past anything created outside "
                        "the generator, which is precisely what is at risk")

    unclaimed = [s for s in steps if s.get("step", "").startswith("unclaimed")]
    # A WORKLOAD AND A VOLUME ARE NOT THE SAME FINDING, and the
    # difference took a correction from the operator to get right.
    # aegis governs what RUNS: an undeclared workload escapes the size
    # policy, the NetworkPolicies and the quota's intent. A volume is
    # different — whether what is inside it matters is something only
    # its owner knows, and the first one this ever found was a
    # deliberate disk of a project that is not aegis's business.
    #
    # So the volume has to be NAMED and it may not be red: the sentence
    # is the alarm, which is this product's own rule. What is checked
    # here is the naming, and the state only for the workloads.
    # AND THE SWEEP HAS TO DISCRIMINATE. A loop that called everything a
    # stranger would satisfy every line above and make the screen
    # useless in the other direction: an operator who is told that the
    # service their contract declares does not belong here learns to
    # ignore the word.
    if "unclaimed:unaorg-web" in named:
        findings.append("the one service the contract DOES declare is also reported as "
                        "unclaimed: a sweep that names everything names nothing")
    for s in unclaimed:
        if s.get("step", "").startswith("unclaimed-volume:"):
            # It has to carry, as DATA, that nothing copies it. That
            # sentence is the whole value of drawing it at all, and it
            # is what a state cannot say.
            if s.get("copiado") is not False:
                findings.append(f"{s['step']} does not say that aegis does not back it "
                                f"up: naming a volume without saying that is naming it "
                                f"for nothing")
            if s.get("state") in ("wrong", "not-evaluable"):
                findings.append(f"{s['step']} is filed as `{s.get('state')}`: a volume the "
                                f"contract does not declare may be a deliberate disk of a "
                                f"project that is not aegis's, and insisting in red about a "
                                f"decision somebody already made teaches them to stop "
                                f"reading the colour")
            continue
        if s.get("state") not in ("wrong", "not-evaluable"):
            findings.append(f"{s['step']} is filed as `{s.get('state')}`: a workload the "
                            f"contract does not declare escapes the size policy, the "
                            f"NetworkPolicies and the quota's intent, and is being reported "
                            f"as being in order")
    if doc.get("rc") == 0:
        findings.append("the document reports rc 0 with a workload in the namespace that "
                        "no contract declares: the command says this organization is exactly "
                        "what it promised to be")

    # And the other half, or the check would pass by calling everything
    # unclaimed: the service that IS declared has to come out fine.
    web = [s for s in steps if s.get("step") == "service:web"]
    if not web:
        findings.append("the one service the contract declares is not in the document")
    elif web[0].get("state") != "already":
        findings.append(f"the declared service is filed as `{web[0].get('state')}` while "
                        f"its workload is ready: the sweep cannot tell a stranger from a "
                        f"tenant")

    for f in findings:
        print(f)
    print(f"SCOPE: 1 declared service, 1 stranger workload and 2 unclaimed volumes "
          f"(100Gi + 5Gi) in front of the command — {len(unclaimed)} named, rc {doc.get('rc')}")
finally:
    shutil.rmtree(home, ignore_errors=True)
