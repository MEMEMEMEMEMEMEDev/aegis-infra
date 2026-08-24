# title: every target namespace is CREATED by somebody trustworthy (bug A)
# origin: verify-static.sh (v2) ══ 23
check() {
# Run #7, bug A: the registry App had CreateNamespace=true but it is
# KUSTOMIZE/KSOPS and the sync failed with "namespaces registry-system
# not found" — CreateNamespace turned out NOT to be trustworthy for
# kustomize apps (it is for HELM ones: cert-manager/infra-edge created
# theirs fine). The discriminator that DOES work: the ns is declared by
# a manifest (namespace.yaml/bundle) OR created by a HELM app with
# CreateNamespace. A kustomize app depending on its OWN CreateNamespace
# is NOT enough.
if python3 - "$AEGIS_ROOT" <<'EOF'
import yaml, glob, pathlib, sys
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
PRE = {"argocd","kube-system","kube-public","kube-node-lease","default"}
apps = []
app_paths = []   # (path) of apps pointing at k8s/ (kustomize/dir)
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
# namespaces created by a REACHABLE Namespace manifest: it is not
# enough for the file to exist — kustomize only applies it if it is
# LISTED in its kustomization (or if it is a directory-app with no
# kustomization). The "exists but not listed" tooth revealed this
# distinction:
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
        # directory-app: kustomize/argo apply EVERY .yaml in the dir
        for y in d.glob("*.yaml"):
            manifest_ns |= ns_in_file(y)
# a HELM app with CreateNamespace creates its ns reliably:
helm_createns = {ns for (_,ns,h,cn) in apps if h and cn}
created = PRE | manifest_ns | helm_createns
ok=True
for name, ns, is_helm, cn in apps:
    if ns not in created:
        why = "CreateNamespace=true BUT kustomize app (not trustworthy)" if cn else "no creator"
        print(f"FAIL App '{name}': ns '{ns}' is created by nobody trustworthy ({why}) "
              f"→ add namespace.yaml to the kustomize (like kyverno-base/trivy)")
        ok=False
print(f"apps cross-checked: {len(apps)}; ns created by manifest={sorted(manifest_ns)}; "
      f"by helm+CreateNs={sorted(helm_createns)}")
sys.exit(0 if ok else 1)
EOF
then pass "every target ns is created by a manifest or by a helm+CreateNamespace app"
else fail "App with an ns that nobody creates reliably (bug A)"; fi
}
