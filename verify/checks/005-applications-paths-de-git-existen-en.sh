# titulo: Applications: paths de git existen en el repo
# origen: verify-static.sh (v2) ══ 5
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"; ok = True; n = 0
seed = root/"seed"/"canary"
for f in (P/"k8s"/"argocd-apps").glob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        srcs = d["spec"].get("sources") or [d["spec"].get("source")]
        for s in srcs:
            if not s or "path" not in s: continue
            n += 1
            # el path se verifica contra el repo que la App declara:
            # plataforma → platform/ del artefacto; APP → el seed
            # del canary (lo que la fase 12 siembra):
            base = seed if "__APP_REPO__" in s.get("repoURL", "") else P
            if not (base/s["path"]).is_dir():
                print(f"FAIL {d['metadata']['name']}: path {s['path']} "
                      f"no existe en {base.name}")
                ok = False
print(f"paths de Apps verificados: {n} (plataforma + seed del canary)")
sys.exit(0 if ok else 1)
EOF
then pass "paths de Applications OK"
else fail "App con path inexistente"; fi
}
