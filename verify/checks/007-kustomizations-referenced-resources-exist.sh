# title: kustomizations: referenced resources exist
# origin: verify-static.sh (v2) ══ 7
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"; ok = True; n = 0
for k in P.rglob("kustomization.yaml"):
    doc = yaml.safe_load(k.open()) or {}
    for r in (doc.get("resources") or []) + (doc.get("generators") or []):
        n += 1
        if not (k.parent/r).exists():
            print(f"FAIL {k.parent.relative_to(P)}: {r} does not exist"); ok = False
print(f"kustomize references verified: {n}")
sys.exit(0 if ok else 1)
EOF
then pass "kustomizations OK"
else fail "kustomization with a broken reference"; fi
}
