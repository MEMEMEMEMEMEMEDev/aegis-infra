# titulo: argo_sync ↔ Applications declaradas (clase del hueco hello-aegis)
# origen: verify-static.sh (v2) ══ 5b
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# Se recorre TODO platform/k8s y no solo argocd-apps/. Una App
# declarada es una App declarada, viva donde viva: desde 2026-07-28 la
# del canary vive en el bundle de su organizacion —que es donde esta su
# dueño unico— y este check, atado a la CARPETA, la dio por inexistente
# sin que nada se hubiera roto. Misma clase C15 que ya obligo a
# ensanchar el sub-check 1 del check 76: un check atado a la ubicacion
# miente en cuanto algo se mueve.
declared = set()
for f in sorted((P/"k8s").rglob("*.yaml")):
    if f.name.endswith(".enc.yaml"):
        continue          # cifrado: no parsea y no declara Applications
    try:
        docs = list(yaml.safe_load_all(f.open()))
    except Exception:
        continue          # plantillas con placeholders: no son YAML aun
    for d in docs:
        if d and d.get("kind") == "Application":
            declared.add(d["metadata"]["name"])
ok = True; synced = set()
for ph in (root/"init"/"phases").glob("*.sh"):
    # solo LLAMADAS reales (líneas no-comentario) — el comentario
    # "argo_sync viene de lib/common.sh" no es una App (mención ≠ uso):
    code = "\n".join(l for l in ph.read_text().splitlines()
                     if not l.lstrip().startswith("#"))
    for m in re.finditer(r'argo_sync\s+([a-z0-9-]+)', code):
        synced.add((m.group(1), ph.name))
for app, ph in sorted(synced):
    if app not in declared:
        print(f"FAIL argo_sync de App NO declarada: {app} ({ph})"); ok = False
print(f"argo_sync verificados: {len(synced)} contra {len(declared)} Apps")
sys.exit(0 if ok else 1)
EOF
then pass "todo argo_sync tiene su Application"
else fail "argo_sync contra App inexistente"; fi
}
