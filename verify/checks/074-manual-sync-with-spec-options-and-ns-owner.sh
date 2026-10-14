# title: manual sync with the spec's OPTIONS + the ns owner first (D v1.2)
# origin: verify-static.sh (v2) ══ 74
check() {
# An EMPTY `operation.sync` does not inherit spec.syncPolicy.syncOptions
# (verified live, ArgoCD v3.4.3: specOpts with CreateNamespace,
# opOpts=null, and no Namespace task in the syncResult). It worked for
# 17 runs by rebound: the AUTO-sync created the ns first. Once we moved
# cert-manager earlier we arrived first → "namespaces not found" — and
# ArgoCD marks "will not retry" for that revision, poisoning the
# auto-sync.
D74=""
ASY74="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY74" | grep -q 'spec.syncPolicy.syncOptions' \
    || D74="$D74 argo_sync does not read the spec's syncOptions;"
echo "$ASY74" | grep -q 'sync_patch=' \
    || D74="$D74 argo_sync does not build the patch with the options;"
# no literal empty patch may remain (the re-fires too):
BAD74="$(echo "$ASY74" | grep -c "p '{\"operation\":{\"sync\":{}}}'" || true)"
(( BAD74 == 0 )) || D74="$D74 $BAD74 sync patches remain WITHOUT options (the re-fires must carry them);"
# every destination namespace has ONE owner (CreateNamespace=true) and
# that owner syncs BEFORE its dependants in phase 35:
if ! python3 - "$AEGIS_ROOT" <<'EOF'
import sys, pathlib, re, yaml
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# GLOBAL sync order: every phase in lexicographic order, and within each
# one, line order (so the check holds for phase 50's
# jenkins-secrets→jenkins, not only for phase 35):
order, seen = [], set()
for ph in sorted((root/"init/phases").glob("[0-9][0-9]-*.sh")):
    for ln in ph.read_text().splitlines():
        s = ln.strip()
        if s.startswith("#"): continue
        m = re.match(r'argo_sync\s+([a-z0-9-]+)', s)
        if m and m.group(1) not in seen:
            seen.add(m.group(1)); order.append(m.group(1))
pos = {a: i for i, a in enumerate(order)}
apps = {}
for f in (P/"k8s"/"argocd-apps").glob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        sp = d["spec"]; ns = sp["destination"].get("namespace")
        opts = (sp.get("syncPolicy") or {}).get("syncOptions") or []
        src = sp.get("source") or {}
        srcs = sp.get("sources") or ([src] if src else [])
        path = next((s.get("path") for s in srcs if s.get("path")), None)
        # TWO valid mechanisms of namespace ownership:
        #  (1) the CreateNamespace=true syncOption (a plain ns), or
        #  (2) a Namespace manifest in the App's path — the MANDATORY
        #      route when the ns carries metadata of its own
        #      (jenkins-system with PSS privileged, org-canary with
        #      restricted): those CANNOT be created blindly.
        declares = False
        if path and (P/path).is_dir():
            for mf in list((P/path).glob("*.yaml")) + list((P/path).glob("*.yml")):
                try: docs = [x for x in yaml.safe_load_all(mf.open()) if x]
                except Exception: continue
                if any(x.get("kind") == "Namespace" and
                       x.get("metadata", {}).get("name") == ns for x in docs):
                    declares = True
        apps[d["metadata"]["name"]] = (ns, "CreateNamespace=true" in opts or declares)
bad = []
owners = {}
for name, (ns, own) in apps.items():
    if own: owners.setdefault(ns, []).append(name)
for name, (ns, own) in apps.items():
    if ns in (None, "argocd", "kube-system", "default"): continue
    if own: continue
    if ns not in owners:
        bad.append(f"App {name} uses ns {ns} and NOBODY creates it (neither CreateNamespace nor a Namespace manifest)")
        continue
    late = [o for o in owners[ns]
            if name in pos and o in pos and pos[o] > pos[name]]
    if late and not any(o in pos and pos[o] < pos[name] for o in owners[ns]):
        bad.append(f"App {name} (sync #{pos[name]}) uses ns {ns} whose owner ({', '.join(late)}) syncs AFTERWARDS")
if bad:
    for b in bad: print("  " + b, file=sys.stderr)
    sys.exit(1)
EOF
then D74="$D74 namespace owner absent or later than its dependants (detail above);"
fi
if [[ -n "$D74" ]]; then fail "manual sync/namespaces:$D74"
else pass "the manual sync propagates the spec's options; every ns has ONE owner and syncs before its dependants"; fi
}
