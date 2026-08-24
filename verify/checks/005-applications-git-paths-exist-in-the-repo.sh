# title: Applications: git paths exist in the repo
# origin: verify-static.sh (v2) ══ 5
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
            # the path is verified against the repo the App declares:
            # platform → platform/ of the artifact; APP → the seed of
            # the canary (what phase 12 sows):
            base = seed if "__APP_REPO__" in s.get("repoURL", "") else P
            if not (base/s["path"]).is_dir():
                print(f"FAIL {d['metadata']['name']}: path {s['path']} "
                      f"does not exist in {base.name}")
                ok = False
print(f"App paths verified: {n} (platform + canary seed)")
sys.exit(0 if ok else 1)
EOF
then pass "Application paths OK"
else fail "App with a nonexistent path"; fi
}
