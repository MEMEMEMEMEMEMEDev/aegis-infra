# title: kustomizations: referenced resources exist
# origin: verify-static.sh (v2) ══ 7
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"; ok = True; n = 0
for k in P.rglob("kustomization.yaml"):
    doc = yaml.safe_load(k.open()) or {}
    # A kustomization.yaml that is not a MAPPING is a broken artifact,
    # and it has to be REPORTED as one. Until 2026-08-24 this line was
    # `doc.get(...)` straight away, so a file that parsed as a list
    # raised AttributeError and the check died with a traceback instead
    # of a verdict — and the runner, seeing rc 1, could not tell that
    # apart from a real red. The check's own tooth was living off that
    # confusion. Same family as check 107: the path that exists to
    # explain a failure must not be able to fail itself.
    if not isinstance(doc, dict):
        print(f"FAIL {k.parent.relative_to(P)}: kustomization.yaml is not a mapping"); ok = False
        continue
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
