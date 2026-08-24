# titulo: quota jenkins-system ≥ jenkins-0 + 2 builds solapados (corrida #11)
# origen: verify-static.sh (v2) ══ 36
check() {
# Aritmética, no fe: con limits.cpu=8, ci-images residual (2500m) +
# build de app (4000m) + jenkins-0 (2200m) = 8700m agotó la RQ y el
# gate colgó. Invariante: quota ≥ jenkins-0 + 2 × pod-de-build-más-
# pesado (reintentos/solapamientos del multibranch = caso normal):
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
    raise ValueError(f"memoria no parseable: {v}")
quota = None
for d in yaml.safe_load_all((P/"k8s/base/platform/jenkins-secrets/bundle.yaml").open()):
    if d and d.get("kind") == "ResourceQuota":
        quota = d["spec"]["hard"]
if not quota:
    print("FAIL no encuentro la ResourceQuota en bundle.yaml"); sys.exit(1)
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
builds = [pod_sum(P/"docs/protocols/templates/Jenkinsfile.app"),
          pod_sum(P/"ci-images/Jenkinsfile")]
bcpu = max(b[0] for b in builds); bmem = max(b[1] for b in builds)
need_cpu, need_mem = jcpu + 2*bcpu, jmem + 2*bmem
print(f"quota={qcpu:.0f}m/{qmem:.0f}Mi  jenkins-0={jcpu:.0f}m/{jmem:.0f}Mi  "
      f"build-max={bcpu:.0f}m/{bmem:.0f}Mi  necesario={need_cpu:.0f}m/{need_mem:.0f}Mi")
if qcpu < need_cpu or qmem < need_mem:
    print("FAIL quota insuficiente para jenkins-0 + 2 builds solapados (la cascada de la corrida #11)")
    sys.exit(1)
sys.exit(0)
EOF
then pass "la RQ de jenkins-system banca jenkins-0 + 2 builds solapados"
else fail "RQ de jenkins-system corta de quota (builds encolados para siempre — corrida #11)"; fi
}
