# title: sync manual con las OPCIONES del spec + dueño del ns primero (D v1.2)
# origen: verify-static.sh (v2) ══ 74
check() {
# Un `operation.sync` VACÍO no hereda spec.syncPolicy.syncOptions
# (verificado en vivo, ArgoCD v3.4.3: specOpts con CreateNamespace,
# opOpts=null, y sin tarea Namespace en el syncResult). Funcionó 17
# corridas de rebote: el AUTO-sync creaba el ns antes. Al adelantar
# cert-manager llegamos primero → "namespaces not found" — y ArgoCD
# marca "will not retry" para esa revisión, envenenando el auto-sync.
D74=""
ASY74="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY74" | grep -q 'spec.syncPolicy.syncOptions' \
    || D74="$D74 argo_sync no lee las syncOptions del spec;"
echo "$ASY74" | grep -q 'sync_patch=' \
    || D74="$D74 argo_sync no construye el patch con las opciones;"
# ningún patch literal vacío debe quedar (los re-disparos también):
BAD74="$(echo "$ASY74" | grep -c "p '{\"operation\":{\"sync\":{}}}'" || true)"
(( BAD74 == 0 )) || D74="$D74 quedan $BAD74 patches de sync SIN opciones (los re-disparos deben llevarlas);"
# cada namespace destino tiene UN dueño (CreateNamespace=true) y ese
# dueño se sincroniza ANTES que sus dependientes en la fase 35:
if ! python3 - "$AEGIS_ROOT" <<'EOF'
import sys, pathlib, re, yaml
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# orden GLOBAL de syncs: todas las fases en orden lexicográfico, y
# dentro de cada una, orden de línea (así el check vale para
# jenkins-secrets→jenkins de la 50, no solo para la 35):
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
        # DOS mecanismos válidos de propiedad del namespace:
        #  (1) syncOption CreateNamespace=true (ns plano), o
        #  (2) un manifiesto Namespace en el path de la App — el
        #      camino OBLIGADO cuando el ns lleva metadata propia
        #      (jenkins-system con PSS privileged, org-canary con
        #      restricted): esos NO se pueden crear a ciegas.
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
        bad.append(f"App {name} usa ns {ns} y NADIE lo crea (ni CreateNamespace ni manifiesto Namespace)")
        continue
    late = [o for o in owners[ns]
            if name in pos and o in pos and pos[o] > pos[name]]
    if late and not any(o in pos and pos[o] < pos[name] for o in owners[ns]):
        bad.append(f"App {name} (sync #{pos[name]}) usa ns {ns} cuyo dueño ({', '.join(late)}) sincroniza DESPUÉS")
if bad:
    for b in bad: print("  " + b, file=sys.stderr)
    sys.exit(1)
EOF
then D74="$D74 dueño del namespace ausente o posterior a sus dependientes (arriba el detalle);"
fi
if [[ -n "$D74" ]]; then fail "sync manual/namespaces:$D74"
else pass "el sync manual propaga las opciones del spec; cada ns tiene UN dueño y sincroniza antes que sus dependientes"; fi

if [[ "${1:-}" == "--with-charts" ]]; then
    echo "══ 13. helm template contra los charts REALES (red) ══"
    # renderiza cada chart adoptado con los values del artefacto;
    # placeholders de config se sustituyen por dummies (solo para el
    # render — el archivo real no se toca).
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    python3 - "$AEGIS_ROOT" > "$TMP/charts.tsv" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
for f in (P/"k8s"/"argocd-apps").glob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        srcs = d["spec"].get("sources") or []
        for s in srcs:
            if "chart" in s:
                vf = s.get("helm", {}).get("valueFiles", [""])[0]
                vf = vf[len("$values/"):] if vf.startswith("$values/") else ""
                print(f'{d["metadata"]["name"]}\t{s["repoURL"]}\t{s["chart"]}\t{s["targetRevision"]}\t{vf}')
EOF
    while IFS=$'\t' read -r app repo chart ver vf; do
        VAL_ARGS=()
        if [[ -n "$vf" && -f "$P/$vf" ]]; then
            sed -e 's/__GH_OWNER__/dummyowner/g' \
                -e 's/__PLATFORM_REPO__/dummyrepo/g' \
                -e 's/__APP_REPO__/dummyapp/g' \
                -e 's/__ROOT_DOMAIN__/example.com/g' \
                -e 's/__REGISTRY_CLUSTER_IP__/10.43.0.99/g' \
                -e 's/__ACME_EMAIL__/a@example.com/g' \
                "$P/$vf" > "$TMP/$app-values.yaml"
            VAL_ARGS=(-f "$TMP/$app-values.yaml")
        fi
        # repos OCI (sin esquema, como los declara ArgoCD — patrón
        # validado en v1 vivo con quay.io/jetstack/charts): helm
        # necesita la forma oci://<repo>/<chart>:
        if [[ "$repo" == http* ]]; then
            CHART_REF=("$chart" --repo "$repo")
        else
            CHART_REF=("oci://$repo/$chart")
        fi
        if helm template "$app" "${CHART_REF[@]}" \
             --version "$ver" "${VAL_ARGS[@]}" \
             --namespace dummy-ns >"$TMP/$app.render" 2>"$TMP/$app.err"; then
            pass "helm template $app ($chart@$ver)"
        else
            fail "helm template $app ($chart@$ver):"
            tail -5 "$TMP/$app.err"
        fi
        # check de EFECTO (no solo "no rompe"): las keys críticas
        # deben APARECER en el render — un values con una key en el
        # lugar equivocado renderiza limpio y no hace nada (el bug
        # configs.cm literal-con-punto que este check encontró):
        if [[ "$app" == argocd ]]; then
            for must in 'enable-alpha-plugins' 'ksops' 'server.insecure'; do
                grep -q "$must" "$TMP/$app.render" \
                    && pass "render argocd contiene '$must'" \
                    || fail "render argocd SIN '$must' (key ignorada?)"
            done
        fi
        # corrida #5 (hallazgo B): service.type en el path viejo era
        # IGNORADO por el chart 40.x → LoadBalancer <pending> eterno.
        # El efecto, no la key: el Service del render DEBE ser
        # ClusterIP y las trustedIPs (A31) DEBEN llegar a los args:
        if [[ "$app" == traefik ]]; then
            grep -q 'type: ClusterIP' "$TMP/$app.render" \
                && ! grep -q 'type: LoadBalancer' "$TMP/$app.render" \
                && pass "render traefik: Service ClusterIP (no LB)" \
                || fail "render traefik NO es ClusterIP (¿key en path que el chart ignora?)"
            grep -q 'forwardedHeaders.trustedIPs=10.42' "$TMP/$app.render" \
                && pass "render traefik: trustedIPs llegan a los args" \
                || fail "render traefik SIN trustedIPs (A31 no aplicada)"
        fi
    done < "$TMP/charts.tsv"
fi
}
