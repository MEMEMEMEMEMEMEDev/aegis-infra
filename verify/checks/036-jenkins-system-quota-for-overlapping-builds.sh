# title: jenkins-system quota ≥ jenkins-0 + 2 overlapping builds (run #11)
# origin: verify-static.sh (v2) ══ 36
check() {
# Arithmetic, not faith: with limits.cpu=8, residual ci-images (2500m)
# + app build (4000m) + jenkins-0 (2200m) = 8700m exhausted the RQ and
# the gate hung. Invariant: quota ≥ jenkins-0 + 2 × heaviest-build-
# pod (multibranch retries/overlaps = the normal case):
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
def cpu_m(v):
    v = str(v).strip().strip('"')
    return int(v[:-1]) if v.endswith("m") else int(float(v)*1000)
def mem_mi(v):
    v = str(v).strip().strip('"')
    if v.endswith("Gi"): return float(v[:-2])*1024
    if v.endswith("Mi"): return float(v[:-2])
    raise ValueError(f"unparseable memory: {v}")
quota = None
for d in yaml.safe_load_all((P/"k8s/base/platform/jenkins-secrets/bundle.yaml").open()):
    if d and d.get("kind") == "ResourceQuota":
        quota = d["spec"]["hard"]
if not quota:
    print("FAIL cannot find the ResourceQuota in bundle.yaml"); sys.exit(1)
# BOTH HALVES OF THE QUOTA. limits is a ceiling; requests is the half
# that IS a reservation, and a pod pending on requests.cpu looks exactly
# like one pending on limits.cpu from the outside. Until 2026-09-20 this
# check read limits only, the bundle's own comment did the requests
# arithmetic by hand, and nothing kept the two together.
Q = {}
for half in ("limits", "requests"):
    Q[half] = (cpu_m(quota[f"{half}.cpu"]), mem_mi(quota[f"{half}.memory"]))
vals = yaml.safe_load((P/"k8s/base/platform/jenkins/values.yaml").open())
# jenkins-0 is the controller plus EVERY sidecar it declares — not one
# sidecar named here by hand, which is how a second one was left off
# the scale. Init containers run before the pod is up, never beside a
# build, so they are not summed.
def jenkins0(half):
    c = vals["controller"]["resources"][half]
    cpu, mem = cpu_m(c["cpu"]), mem_mi(c["memory"])
    for name, side in (vals["controller"].get("sidecars") or {}).items():
        r = (side.get("resources") or {}).get(half) or {}
        if "cpu" in r and "memory" in r:
            cpu += cpu_m(r["cpu"]); mem += mem_mi(r["memory"])
    return cpu, mem
def pod_sum(path, half):
    """Every `<half>:` block of a pipeline's inline pod YAML, in BOTH
    spellings — the flow map `limits: { cpu: 1, memory: 1Gi }` and the
    block form with cpu/memory on their own lines. A pipeline written
    in the block style used to weigh zero here, silently."""
    text = path.read_text()
    cpu = mem = 0.0
    for m in re.finditer(rf'{half}:\s*\{{\s*cpu:\s*([^,]+),\s*memory:\s*([^}}\s]+)\s*\}}', text):
        cpu += cpu_m(m.group(1)); mem += mem_mi(m.group(2))
    for m in re.finditer(rf'{half}:\s*\n\s+cpu:\s*([^\n]+)\n\s+memory:\s*([^\n]+)', text):
        cpu += cpu_m(m.group(1)); mem += mem_mi(m.group(2))
    for m in re.finditer(rf'{half}:\s*\n\s+memory:\s*([^\n]+)\n\s+cpu:\s*([^\n]+)', text):
        cpu += cpu_m(m.group(2)); mem += mem_mi(m.group(1))    # and the JSON spelling: base-images starts its candidate as a pod
    # built from a JSON literal (check 223), and that pod sits in this
    # namespace beside the agent while it runs.
    for m in re.finditer(rf'"{half}":\{{"cpu":"([^"]+)","memory":"([^"]+)"\}}', text):
        cpu += cpu_m(m.group(1)); mem += mem_mi(m.group(2))
    return cpu, mem
# EVERY pipeline the platform runs in jenkins-system, not a list of
# two. Until 2026-08-27 this summed Jenkinsfile.app and ci-images only,
# and the day base-images and image-watch arrived (each with its own
# kaniko or trivy) the heaviest pod could have moved without this
# noticing: the arithmetic was right about a platform that no longer
# existed. The list is DERIVED from the tree: seed/platform/*/Jenkinsfile
# plus the tenant template.
#
# AND THE DERIVATION HAS TO REACH. Until 2026-09-01 this globbed
# `*/Jenkinsfile`, one level deep, so when the AI lanes landed in
# ai/engine-gpu/ and ai/engine-cpu/ they were invisible — to the very
# instrument whose job is to find the heaviest pod. engine-gpu sums
# 12544Mi against a 12Gi quota: it could never be scheduled at all,
# and this check reported ALL PASS with build-max=4608Mi. The exact
# failure it was written to prevent, committed by itself. rglob now,
# and any name starting with Jenkinsfile, so neither nesting nor a
# suffix can hide a pipeline again.
jfs = sorted({f for f in P.rglob("Jenkinsfile*") if f.is_file()})
# AND THE COVERAGE IS PROVED, not assumed. Reaching deeper is not
# enough on its own: a derivation that silently misses a pipeline
# makes this check pass, so the miss is invisible by construction —
# which is exactly what happened. So the set found here is measured
# against a DIFFERENT source: every scriptPath the job-dsl declares.
# If Jenkins is configured to run a pipeline whose pod this
# arithmetic never weighed, that is the failure, said out loud.
dsl = (P/"k8s/base/platform/jenkins/values.yaml").read_text(encoding="utf-8")
declared = set(re.findall(r"scriptPath\('([^']+)'\)", dsl))
found = {str(f.relative_to(P)) for f in jfs}
# The tenant template is NOT in the job-dsl — every organization
# derives its own job from it — so the dsl cannot vouch for it and it
# is named here on purpose. The previous version required it by
# construction (it was a literal in the list); rglob made its absence
# silent, and the tooth for exactly that stopped biting.
TPL = "docs/protocols/templates/Jenkinsfile.app"
missing = sorted(declared - found) + ([TPL] if TPL not in found else [])
if missing:
    print("FAIL pipelines this arithmetic never weighed: "
          + ", ".join(missing)
          + " — a pod that is not on the scale cannot make the quota short")
    sys.exit(1)
short = []
for half in ("limits", "requests"):
    builds = {}
    for jf in jfs:
        if not jf.is_file():
            print(f"FAIL {jf.relative_to(P)} does not exist"); sys.exit(1)
        builds[str(jf.relative_to(P))] = pod_sum(jf, half)
    if len(builds) < 2:
        print("FAIL fewer than two pipelines found under seed/platform/*/Jenkinsfile: the tree is not the one this arithmetic knows"); sys.exit(1)
    if half == "limits" and any(v == (0.0, 0.0) for v in builds.values()):
        zero = [k for k, v in builds.items() if v == (0.0, 0.0)]
        print("FAIL pipelines whose pod weighs ZERO on this scale: " + ", ".join(zero)
              + " — a pod with no limits this regex can read is not weightless, it is unread")
        sys.exit(1)
    heaviest = max(builds, key=lambda k: builds[k][0])
    bcpu = max(b[0] for b in builds.values()); bmem = max(b[1] for b in builds.values())
    jcpu, jmem = jenkins0(half)
    qcpu, qmem = Q[half]
    print(f"  [{half}] " + "  ".join(f"{k}={v[0]:.0f}m/{v[1]:.0f}Mi" for k, v in builds.items()))
    need_cpu, need_mem = jcpu + 2*bcpu, jmem + 2*bmem
    print(f"  [{half}] quota={qcpu:.0f}m/{qmem:.0f}Mi  jenkins-0={jcpu:.0f}m/{jmem:.0f}Mi  "
          f"build-max={bcpu:.0f}m/{bmem:.0f}Mi ({heaviest})  needed={need_cpu:.0f}m/{need_mem:.0f}Mi")
    if qcpu < need_cpu or qmem < need_mem:
        short.append(half)
if short:
    print(f"FAIL quota insufficient for jenkins-0 + 2 overlapping builds on {', '.join(short)} (the cascade of run #11)")
    sys.exit(1)
sys.exit(0)
EOF
then pass "the jenkins-system RQ carries jenkins-0 (controller + every sidecar) + 2 overlapping builds, on limits AND on requests, with every pipeline's pod weighed in either YAML spelling"
else fail "jenkins-system RQ short on quota (builds queued forever — run #11)"; fi
}
