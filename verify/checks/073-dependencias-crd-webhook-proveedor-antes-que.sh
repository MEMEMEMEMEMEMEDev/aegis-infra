# titulo: dependencias CRD/webhook: proveedor ANTES que consumidor (A v1.1)
# origen: verify-static.sh (v2) ══ 73
check() {
# Hallazgo A v1.1 (6ª instancia de la familia): argocd-secrets
# sincronizaba PRIMERA y contenía un Certificate — cuyo webhook lo
# provee cert-manager, sincronizado DESPUÉS. Determinista en frío.
# Este check lee el ORDEN REAL de argo_sync en la fase 35 y exige
# que toda App que contenga recursos de un dominio (cert-manager.io,
# traefik.io, kyverno.io) se sincronice DESPUÉS de su proveedor:
D73=""
if ! python3 - "$AEGIS_ROOT" <<'EOF'
import sys, pathlib, re, yaml
root = pathlib.Path(sys.argv[1]); P = root/"semilla"/"plataforma"
# 1) orden real de syncs en la fase 35 (líneas no-comentario):
order, seen = [], set()
for ln in (root/"init/phases/35-gitops.sh").read_text().splitlines():
    s = ln.strip()
    if s.startswith("#"): continue
    m = re.match(r'argo_sync\s+([a-z0-9-]+)', s)
    if m and m.group(1) not in seen:
        seen.add(m.group(1)); order.append(m.group(1))
pos = {a: i for i, a in enumerate(order)}
# 2) path de cada App (una App = un dir de manifests):
apps = {}
for f in (P/"k8s"/"argocd-apps").glob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        src = d["spec"].get("source") or {}
        srcs = d["spec"].get("sources") or ([src] if src else [])
        for s in srcs:
            if s.get("path"):
                apps[d["metadata"]["name"]] = s["path"]
# 3) proveedor de cada dominio de API:
providers = {"cert-manager.io": "cert-manager",
             "traefik.io": "traefik",
             "kyverno.io": "kyverno"}
bad = []
for app, path in apps.items():
    if app not in pos: continue          # no lo sincroniza la 35
    d = P/path
    if not d.is_dir(): continue
    for f in list(d.glob("*.yaml")) + list(d.glob("*.yml")):
        try: docs = [x for x in yaml.safe_load_all(f.open()) if x]
        except Exception: continue
        for doc in docs:
            api = str(doc.get("apiVersion", ""))
            dom = api.split("/")[0]
            prov = providers.get(dom)
            if not prov or prov == app: continue
            if prov not in pos:
                bad.append(f"{app} usa {dom} ({doc.get('kind')}) y su proveedor {prov} NO se sincroniza en la 35")
            elif pos[prov] > pos[app]:
                bad.append(f"{app} (sync #{pos[app]}) contiene {doc.get('kind')}/{dom} pero su proveedor {prov} sincroniza DESPUÉS (#{pos[prov]}) — dependencia INVERTIDA")
if bad:
    for b in bad: print("  " + b, file=sys.stderr)
    sys.exit(1)
EOF
then D73="$D73 dependencia invertida CRD/webhook (arriba el detalle);"
fi
# el helper genérico existe y la 35 lo usa sobre cert-manager (el
# Healthy de la App NO prueba que el webhook atienda):
nc "$LIBS/common.sh" | grep -q '^webhook_serving()' \
    || D73="$D73 falta el helper webhook_serving (endpoints, no Healthy);"
# la firma del webhook-no-atiende debe cubrir el texto REAL de la
# corrida y NO enmascarar un manifiesto roto (probado en vivo acá):
if ! bash -c "source <(grep '^AEGIS_WEBHOOK_NOTREADY_SIGS=' "$LIBS/common.sh")
      grep -qiE \"\$AEGIS_WEBHOOK_NOTREADY_SIGS\" <<< 'failed calling webhook \"webhook.cert-manager.io\": no endpoints available for service' \
      && ! grep -qiE \"\$AEGIS_WEBHOOK_NOTREADY_SIGS\" <<< 'manifest is invalid: missing required field'" 2>/dev/null; then
    D73="$D73 la firma de webhook-no-atiende no cubre el error real (o enmascara un manifiesto roto);"
fi
ASY73="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY73" | grep -q 'wh_refires' \
    || D73="$D73 argo_sync sin reintento LARGO para webhook no listo (3x10s era insuficiente: 1-2 min desde cero);"
echo "$ASY73" | grep -q 'syncResult.resources\[\]\?.message' \
    || D73="$D73 argo_sync clasifica por el SÍNTOMA de la App y no lee la causa del detalle por recurso;"
NC35="$(nc "$FASES/35-gitops.sh")"
echo "$NC35" | grep -q 'webhook_serving cert-manager' \
    || D73="$D73 la 35 no espera ENDPOINTS del webhook de cert-manager;"
L_CM="$(awk '!/^[[:space:]]*#/ && /argo_sync cert-manager /{print NR; exit}' "$FASES/35-gitops.sh")"
L_WH="$(awk '!/^[[:space:]]*#/ && /webhook_serving cert-manager/{print NR; exit}' "$FASES/35-gitops.sh")"
L_SEC="$(awk '!/^[[:space:]]*#/ && /argo_sync argocd-secrets/{print NR; exit}' "$FASES/35-gitops.sh")"
L_SELF="$(awk '!/^[[:space:]]*#/ && /argo_sync argocd /{print NR; exit}' "$FASES/35-gitops.sh")"
if [[ -z "$L_CM" || -z "$L_WH" || -z "$L_SEC" ]] || ! (( L_CM < L_WH && L_WH < L_SEC )); then
    D73="$D73 el orden cert-manager → webhook servido → argocd-secrets no se respeta;"
fi
# la restricción VIEJA sigue viva (argocd-secrets antes que el self,
# o el puntero \$github-webhook:token queda literal — ADR-0015):
if [[ -z "$L_SELF" ]] || ! (( L_SEC < L_SELF )); then
    D73="$D73 argocd-secrets dejó de ir antes de argocd-self (ADR-0015);"
fi
# Hallazgo C: los comandos que se imprimen para copiar-pegar tienen
# que funcionar desde CUALQUIER cwd — el operador los copia desde otro
# directorio, y `./init/aegis-init.sh --from 50` ahí no existe.
#
# En v2 el criterio era «que sea absoluto» y el renglón decía
# `$INIT_DIR/aegis-init.sh`. En v3 el criterio se cumple mejor: el
# comando es `aegis init`, que está en el PATH (la fase 05 lo instala
# como symlink) y sale de $AEGIS_CMD, nunca literal — la regla de
# clase contra los ~155 strings de la Clase E. Lo que este check
# prohíbe es la forma RELATIVA, que es la que fallaba.
RETOME="$(nc "$LIBEXEC/aegis-init" | grep 'Retomar:' | head -1)"
if [[ -z "$RETOME" ]]; then
    D73="$D73 C: el init ya no imprime cómo retomar;"
elif ! grep -q 'AEGIS_CMD' <<< "$RETOME" && ! grep -qE 'Retomar: (/|\$AEGIS_ROOT)' <<< "$RETOME"; then
    D73="$D73 C: el comando de retome no se puede pegar desde otro cwd ($RETOME);"
fi
if [[ -n "$D73" ]]; then fail "dependencias/UX:$D73"
else pass "proveedores antes que consumidores (orden real de la 35 verificado), webhook por ENDPOINTS, retome absoluto"; fi
}
