# title: argocd adoption contract (single source)
# origin: verify-static.sh (v2) ══ 6
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
docs = [d for d in yaml.safe_load_all((P/"k8s"/"argocd-apps"/"core.yaml").open()) if d]
app = next(d for d in docs if d.get("kind")=="Application"
           and d["metadata"]["name"]=="argocd")
h = next(s for s in app["spec"]["sources"] if "chart" in s)
ok = True
if h["helm"].get("releaseName") != "argocd":
    print("FAIL releaseName != argocd"); ok = False
vf = h["helm"]["valueFiles"][0]
if not vf.startswith("$values/"):
    print(f"FAIL valueFiles without $values: {vf}"); ok = False
elif not (P/vf[len("$values/"):]).is_file():
    print(f"FAIL values does not exist: {vf}"); ok = False
# phase 30 must have no LITERAL pin of its own (reading the
# "targetRevision" key from the YAML is fine; a hardcoded version is
# not):
import re
f30 = (root/"init"/"phases"/"30-argocd.sh").read_text()
if re.search(r'(chart_pins|ARGO_CHART_VER=\s*"[0-9])', f30) or \
   re.search(r'targetRevision:\s*[0-9]', f30):
    print("FAIL phase 30 has a pin of its own (it must derive it from core.yaml)"); ok = False
# with redisSecretInit=false the chart does NOT create argocd-redis and
# the redis container demands it (verified against the 9.5.20 render):
# phase 30 MUST create it before the install:
if "argocd-redis" not in f30:
    print("FAIL phase 30 does not create argocd-redis (required with the Job off)"); ok = False
print(f"contract: {h['chart']}@{h['targetRevision']} release={h['helm']['releaseName']}")
sys.exit(0 if ok else 1)
EOF
then pass "adoption contract: single source core.yaml"
else fail "adoption contract broken"; fi
}
