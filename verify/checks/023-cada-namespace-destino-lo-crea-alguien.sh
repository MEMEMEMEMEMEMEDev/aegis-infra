# titulo: cada namespace destino lo CREA alguien confiable (bug A)
# origen: verify-static.sh (v2) ══ 23
check() {
# Corrida #7, bug A: la App registry tenía CreateNamespace=true pero
# es KUSTOMIZE/KSOPS y el sync falló "namespaces registry-system not
# found" — CreateNamespace resultó NO confiable para apps kustomize
# (sí para HELM: cert-manager/infra-edge lo crearon bien). El
# discriminador que SÍ funciona: el ns lo declara un manifest
# (namespace.yaml/bundle) O lo crea un app HELM con CreateNamespace.
# Un app kustomize que depende de su PROPIO CreateNamespace NO basta.
if python3 - "$AEGIS_ROOT" <<'EOF'
import yaml, glob, pathlib, sys
root = pathlib.Path(sys.argv[1]); P = root/"semilla"/"plataforma"
PRE = {"argocd","kube-system","kube-public","kube-node-lease","default"}
apps = []
app_paths = []   # (path) de apps que apuntan a k8s/ (kustomize/dir)
for f in glob.glob(str(P/"k8s"/"argocd-apps"/"*.yaml")):
    for d in yaml.safe_load_all(open(f)):
        if not d or d.get("kind")!="Application": continue
        spec=d["spec"]; srcs=spec.get("sources") or ([spec["source"]] if "source" in spec else [])
        is_helm=any("chart" in s for s in srcs)
        so=spec.get("syncPolicy",{}).get("syncOptions",[]) or []
        cn=any("CreateNamespace=true" in x for x in so)
        apps.append((d["metadata"]["name"], spec.get("destination",{}).get("namespace","?"), is_helm, cn))
        for s in srcs:
            if s.get("path"): app_paths.append(s["path"])
# namespaces creados por un manifest Namespace ALCANZABLE: no basta
# que el archivo exista — kustomize solo lo aplica si está LISTADO en
# su kustomization (o si es un directory-app sin kustomization). El
# teeth "existe pero no listado" reveló esta distinción:
def ns_in_file(path):
    out=set()
    try: docs=list(yaml.safe_load_all(open(path)))
    except Exception: return out
    for d in docs:
        if d and d.get("kind")=="Namespace": out.add(d["metadata"]["name"])
    return out
manifest_ns = set()
for ap in set(app_paths):
    d = P/ap
    if not d.is_dir(): continue
    kfile = d/"kustomization.yaml"
    if kfile.exists():
        try: listed=set((yaml.safe_load(kfile.open()) or {}).get("resources",[]) or [])
        except Exception: listed=set()
        for r in listed:
            manifest_ns |= ns_in_file(d/r)
    else:
        # directory-app: kustomize/argo aplican TODO .yaml del dir
        for y in d.glob("*.yaml"):
            manifest_ns |= ns_in_file(y)
# un HELM con CreateNamespace crea su ns de forma confiable:
helm_createns = {ns for (_,ns,h,cn) in apps if h and cn}
created = PRE | manifest_ns | helm_createns
ok=True
for name, ns, is_helm, cn in apps:
    if ns not in created:
        why = "CreateNamespace=true PERO app kustomize (no confiable)" if cn else "sin creador"
        print(f"FAIL App '{name}': ns '{ns}' no lo crea nadie confiable ({why}) "
              f"→ agregar namespace.yaml al kustomize (como kyverno-base/trivy)")
        ok=False
print(f"apps cruzadas: {len(apps)}; ns creados por manifest={sorted(manifest_ns)}; "
      f"por helm+CreateNs={sorted(helm_createns)}")
sys.exit(0 if ok else 1)
EOF
then pass "todo ns destino lo crea un manifest o un app helm+CreateNamespace"
else fail "App con ns que nadie crea de forma confiable (bug A)"; fi
}
