# title: the canary complies with org-canary's PSS restricted (run #12)
# origin: verify-static.sh (v2) ══ 40
check() {
# org-canary is enforce=restricted; a Deployment with an empty
# securityContext would be REJECTED by the API server as soon as the
# signature let it through. The full profile is demanded in the seed +
# a numeric USER in the Containerfile (runAsNonRoot with a root image
# fails at runtime, not at admission):
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1])
ok = True; n = 0
for f in (root/"seed"/"canary"/"k8s").rglob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Deployment": continue
        n += 1
        spec = d["spec"]["template"]["spec"]
        psc = spec.get("securityContext") or {}
        if psc.get("runAsNonRoot") is not True:
            print(f"FAIL {f.name}/{d['metadata']['name']}: without runAsNonRoot:true"); ok = False
        if (psc.get("seccompProfile") or {}).get("type") != "RuntimeDefault":
            print(f"FAIL {f.name}/{d['metadata']['name']}: without seccompProfile RuntimeDefault"); ok = False
        for c in spec.get("containers", []):
            csc = c.get("securityContext") or {}
            if csc.get("allowPrivilegeEscalation") is not False:
                print(f"FAIL {f.name}/{c['name']}: without allowPrivilegeEscalation:false"); ok = False
            if "ALL" not in ((csc.get("capabilities") or {}).get("drop") or []):
                print(f"FAIL {f.name}/{c['name']}: without capabilities.drop [ALL]"); ok = False
cf = (root/"seed"/"canary"/"Containerfile").read_text()
import re
if not re.search(r'^USER\s+\d+', cf, re.M):
    print("FAIL Containerfile without a numeric USER (runAsNonRoot would fail at runtime)"); ok = False
print(f"seed Deployments verified against restricted: {n}")
sys.exit(0 if ok and n > 0 else 1)
EOF
then pass "the canary declares the full restricted profile (+ numeric USER in the image)"
else fail "the canary does NOT comply with PSS restricted (the API server would reject it after the signature)"; fi
}
