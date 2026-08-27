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
qcpu, qmem = cpu_m(quota["limits.cpu"]), mem_mi(quota["limits.memory"])
vals = yaml.safe_load((P/"k8s/base/platform/jenkins/values.yaml").open())
c = vals["controller"]["resources"]["limits"]
s = vals["controller"]["sidecars"]["configAutoReload"]["resources"]["limits"]
jcpu, jmem = cpu_m(c["cpu"])+cpu_m(s["cpu"]), mem_mi(c["memory"])+mem_mi(s["memory"])
def pod_sum(path):
    cpu = mem = 0.0
    for m in re.finditer(r'limits:\s*\{\s*cpu:\s*([^,]+),\s*memory:\s*([^}\s]+)\s*\}',
                         path.read_text()):
        cpu += cpu_m(m.group(1)); mem += mem_mi(m.group(2))
    return cpu, mem
# EVERY pipeline the platform runs in jenkins-system, not a list of
# two. Until 2026-08-27 this summed Jenkinsfile.app and ci-images only,
# and the day base-images and image-watch arrived (each with its own
# kaniko or trivy) the heaviest pod could have moved without this
# noticing: the arithmetic was right about a platform that no longer
# existed. The list is DERIVED from the tree: seed/platform/*/Jenkinsfile
# plus the tenant template.
jfs = sorted(P.glob("*/Jenkinsfile")) + [P/"docs/protocols/templates/Jenkinsfile.app"]
builds = {}
for jf in jfs:
    if not jf.is_file():
        print(f"FAIL {jf.relative_to(P)} does not exist"); sys.exit(1)
    builds[str(jf.relative_to(P))] = pod_sum(jf)
if len(builds) < 2:
    print("FAIL fewer than two pipelines found under seed/platform/*/Jenkinsfile: the tree is not the one this arithmetic knows"); sys.exit(1)
heaviest = max(builds, key=lambda k: builds[k][0])
bcpu = max(b[0] for b in builds.values()); bmem = max(b[1] for b in builds.values())
print("  " + "  ".join(f"{k}={v[0]:.0f}m/{v[1]:.0f}Mi" for k, v in builds.items()))
need_cpu, need_mem = jcpu + 2*bcpu, jmem + 2*bmem
print(f"quota={qcpu:.0f}m/{qmem:.0f}Mi  jenkins-0={jcpu:.0f}m/{jmem:.0f}Mi  "
      f"build-max={bcpu:.0f}m/{bmem:.0f}Mi ({heaviest})  needed={need_cpu:.0f}m/{need_mem:.0f}Mi")
if qcpu < need_cpu or qmem < need_mem:
    print("FAIL quota insufficient for jenkins-0 + 2 overlapping builds (the cascade of run #11)")
    sys.exit(1)
sys.exit(0)
EOF
then pass "the jenkins-system RQ carries jenkins-0 + 2 overlapping builds"
else fail "jenkins-system RQ short on quota (builds queued forever — run #11)"; fi
}
