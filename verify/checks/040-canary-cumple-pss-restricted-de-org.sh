# titulo: canary cumple PSS restricted de org-canary (corrida #12)
# origen: verify-static.sh (v2) ══ 40
check() {
# org-canary es enforce=restricted; un Deployment con
# securityContext vacío sería RECHAZADO por el API server apenas la
# firma deje pasar. Se exige el perfil completo en el seed + USER
# numérico en el Containerfile (runAsNonRoot con imagen-root falla en
# runtime, no en admission):
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1])
ok = True; n = 0
for f in (root/"semilla"/"canario"/"k8s").rglob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Deployment": continue
        n += 1
        spec = d["spec"]["template"]["spec"]
        psc = spec.get("securityContext") or {}
        if psc.get("runAsNonRoot") is not True:
            print(f"FAIL {f.name}/{d['metadata']['name']}: sin runAsNonRoot:true"); ok = False
        if (psc.get("seccompProfile") or {}).get("type") != "RuntimeDefault":
            print(f"FAIL {f.name}/{d['metadata']['name']}: sin seccompProfile RuntimeDefault"); ok = False
        for c in spec.get("containers", []):
            csc = c.get("securityContext") or {}
            if csc.get("allowPrivilegeEscalation") is not False:
                print(f"FAIL {f.name}/{c['name']}: sin allowPrivilegeEscalation:false"); ok = False
            if "ALL" not in ((csc.get("capabilities") or {}).get("drop") or []):
                print(f"FAIL {f.name}/{c['name']}: sin capabilities.drop [ALL]"); ok = False
cf = (root/"semilla"/"canario"/"Containerfile").read_text()
import re
if not re.search(r'^USER\s+\d+', cf, re.M):
    print("FAIL Containerfile sin USER numérico (runAsNonRoot fallaría en runtime)"); ok = False
print(f"Deployments del seed verificados contra restricted: {n}")
sys.exit(0 if ok and n > 0 else 1)
EOF
then pass "el canary declara el perfil restricted completo (+USER numérico en imagen)"
else fail "canary NO cumple PSS restricted (el API server lo rechazaría tras la firma)"; fi
}
