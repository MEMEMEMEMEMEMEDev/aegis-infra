# title: argo_sync ↔ declared Applications (class of the hello-aegis hole)
# origin: verify-static.sh (v2) ══ 5b
check() {
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# ALL of platform/k8s is walked and not only argocd-apps/. A declared
# App is a declared App, wherever it lives: since 2026-07-28 the
# canary's lives in the bundle of its organization —which is where its
# single owner is— and this check, tied to the FOLDER, took it for
# nonexistent without anything having broken. Same class C15 that
# already forced sub-check 1 of check 76 to be widened: a check tied to
# the location lies as soon as something moves.
declared = set()
for f in sorted((P/"k8s").rglob("*.yaml")):
    if f.name.endswith(".enc.yaml"):
        continue          # encrypted: does not parse and declares no Applications
    try:
        docs = list(yaml.safe_load_all(f.open()))
    except Exception:
        continue          # templates with placeholders: not YAML yet
    for d in docs:
        if d and d.get("kind") == "Application":
            declared.add(d["metadata"]["name"])
ok = True; synced = set()
for ph in (root/"init"/"phases").glob("*.sh"):
    # only real CALLS (non-comment lines) — the comment "argo_sync
    # comes from lib/common.sh" is not an App (mention ≠ use):
    code = "\n".join(l for l in ph.read_text().splitlines()
                     if not l.lstrip().startswith("#"))
    for m in re.finditer(r'argo_sync\s+([a-z0-9-]+)', code):
        synced.add((m.group(1), ph.name))
for app, ph in sorted(synced):
    if app not in declared:
        print(f"FAIL argo_sync of an App that is NOT declared: {app} ({ph})"); ok = False
print(f"argo_sync verified: {len(synced)} against {len(declared)} Apps")
sys.exit(0 if ok else 1)
EOF
then pass "every argo_sync has its Application"
else fail "argo_sync against a nonexistent App"; fi
}
