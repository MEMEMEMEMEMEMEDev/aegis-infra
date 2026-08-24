# titulo: contrato de adopción de argocd (fuente única)
# origen: verify-static.sh (v2) ══ 6
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
    print(f"FAIL valueFiles sin $values: {vf}"); ok = False
elif not (P/vf[len("$values/"):]).is_file():
    print(f"FAIL values no existe: {vf}"); ok = False
# la fase 30 no debe tener ningún pin LITERAL propio (leer la key
# "targetRevision" del YAML está bien; una versión hardcodeada no):
import re
f30 = (root/"init"/"phases"/"30-argocd.sh").read_text()
if re.search(r'(chart_pins|ARGO_CHART_VER=\s*"[0-9])', f30) or \
   re.search(r'targetRevision:\s*[0-9]', f30):
    print("FAIL fase 30 tiene pin propio (debe derivar de core.yaml)"); ok = False
# con redisSecretInit=false el chart NO crea argocd-redis y el
# container redis lo exige (verificado contra el render 9.5.20):
# la fase 30 DEBE crearlo antes del install:
if "argocd-redis" not in f30:
    print("FAIL fase 30 no crea argocd-redis (requerido con Job off)"); ok = False
print(f"contrato: {h['chart']}@{h['targetRevision']} release={h['helm']['releaseName']}")
sys.exit(0 if ok else 1)
EOF
then pass "contrato de adopción: fuente única core.yaml"
else fail "contrato de adopción roto"; fi
}
