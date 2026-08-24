# titulo: kustomizations: resources referenciados existen
# origen: verify-static.sh (v2) ══ 7
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"semilla"/"plataforma"; ok = True; n = 0
for k in P.rglob("kustomization.yaml"):
    doc = yaml.safe_load(k.open()) or {}
    for r in (doc.get("resources") or []) + (doc.get("generators") or []):
        n += 1
        if not (k.parent/r).exists():
            print(f"FAIL {k.parent.relative_to(P)}: {r} no existe"); ok = False
print(f"referencias de kustomize verificadas: {n}")
sys.exit(0 if ok else 1)
EOF
then pass "kustomizations OK"
else fail "kustomization con referencia rota"; fi
}
