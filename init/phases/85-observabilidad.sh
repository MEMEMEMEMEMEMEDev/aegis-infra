#!/usr/bin/env bash
# FASE 85 — observabilidad (fase-85.md, ejecutado; diseño en
# observability/design.md). POR QUÉ 85: cuando corre ya existe TODO
# lo que va a observar (registry con TLS, Jenkins con builds, Kyverno
# en Enforce, el túnel vivo) — una fase de observabilidad antes de
# sus observados solo tendría gates triviales, y un gate que no puede
# fallar no mide nada.
#
# Orden interno = §6 del plano, 12 pasos: traer de la semilla →
# render → secretos → AppProjects → borde → enchufes → root →
# productores-antes-que-consumidores → re-sync de los observados →
# ingesta del histórico → gates. Idempotente para `--only 85` sobre
# instancia viva: gen_or_restore reusa credenciales, las
# copias/entries tienen guard ESTRUCTURAL (jamás grep de mención —
# H4), el render es no-op sin placeholders vivos, argo_sync es
# idempotente, y la ingesta re-sube el gates.jsonl (duplicados en
# vlogs-eventos: aceptado — es historia de bootstraps, se deduplica
# en query por ts+gate; un estado "ya ingesté hasta acá" sería más
# mecanismo que el problema — §9).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 reporte in-VM #14: esta fase MUTA el repo de plataforma — el
# clone local puede estar detrás del remoto. Sincronizar ANTES:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

# argo_sync viene de lib/common.sh (bug C corrida #8) — jamás una
# definición local.

SEMILLA_PLATAFORMA="$AEGIS_ROOT/semilla/plataforma"
B="$PLATFORM_DIR/k8s/base"
OBS="$B/observability"
TOFU="$PLATFORM_DIR/tofu/tofu-apply.sh"
TUNNEL_ENV="$PLATFORM_DIR/tofu/envs/cloudflare-tunnel"

# ── 85.2 TRAER DE LA SEMILLA lo que la instancia no tenga ──────────
# La regla de RUTA.md («entra por semilla/+init/ o no entró»)
# aplicada al caso instancia-viva, donde la fase 10 NO re-siembra
# (platform/ con .git es la verdad). En arranque virgen todo esto es
# no-op: la semilla ya lo trae.
#
# (a) archivos NUEVOS: copiar verbatim si faltan.
if [[ ! -d "$OBS" ]]; then
    run_cmd cp -a "$SEMILLA_PLATAFORMA/k8s/base/observability" "$OBS"
    log_ok "k8s/base/observability/ copiado de la semilla (instancia viva sin observabilidad)"
fi
APPS_OBS="$PLATFORM_DIR/k8s/argocd-apps/observability.yaml"
if [[ ! -f "$APPS_OBS" ]]; then
    run_cmd cp -a "$SEMILLA_PLATAFORMA/k8s/argocd-apps/observability.yaml" "$APPS_OBS"
    log_ok "argocd-apps/observability.yaml copiado de la semilla"
fi
# grafana.tf: archivo NUEVO y no edición de main.tf A PROPÓSITO
# (fase-85 §5): HCL fusiona todos los .tf del directorio — un archivo
# nuevo se copia verbatim a una instancia viva sin cirugía de merge.
GRTF="$PLATFORM_DIR/tofu/modules/cloudflare-access/grafana.tf"
if [[ ! -f "$GRTF" ]]; then
    if [[ -f "$SEMILLA_PLATAFORMA/tofu/modules/cloudflare-access/grafana.tf" ]]; then
        run_cmd cp -a "$SEMILLA_PLATAFORMA/tofu/modules/cloudflare-access/grafana.tf" "$GRTF"
        log_ok "cloudflare-access/grafana.tf copiado de la semilla"
    else
        # fase-85 §12: la Access App de grafana es entregable de B4.
        # Fail-closed y RUIDOSO: seguir sin ella publicaría
        # grafana.<dom> con su login como única cerradura.
        die "falta tofu/modules/cloudflare-access/grafana.tf (semilla e instancia) — prerequisito B4 (fase-85 §5/§12): sin la Access App de grafana NO se expone el hostname; completar B4 y re-correr la fase"
    fi
fi

# (b) entries guardadas en archivos EXISTENTES — guard ESTRUCTURAL
# (yaml_lists_file: entry real de lista, jamás grep de mención — H4)
# y escritura que VALIDA el YAML resultante ANTES de tocar el archivo
# (patrón inject_placeholder — fase-85 §9: si no parsea, intacto).
_yaml_insert_after() {   # <yaml> <regex-de-anclaje> <línea-a-insertar>
    python3 - "$1" "$2" "$3" <<'EOF'
import re, sys, yaml
p, ancla, linea = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(p).read()
lines = text.splitlines()
hits = [i for i, l in enumerate(lines)
        if re.search(ancla, l) and not l.lstrip().startswith("#")]
if len(hits) != 1:
    sys.exit(f"_yaml_insert_after: ancla {ancla!r} con {len(hits)} ocurrencias "
             f"no-comentario en {p} (se exige EXACTAMENTE 1)")
lines.insert(hits[0] + 1, linea)
out = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"_yaml_insert_after: el YAML resultante de {p} NO parsea ({e}) "
             f"— el archivo queda INTACTO")
open(p, "w").write(out)
EOF
}

# sourceRepos ×3 en el AppProject aegis-platform (enumerados, NO '*'
# — deben matchear repoURL exacto de observability.yaml):
APPPROJ="$PLATFORM_DIR/k8s/bootstrap/appprojects.yaml"
for _repo in 'https://victoriametrics.github.io/helm-charts' \
             'https://helm.vector.dev' \
             'https://grafana.github.io/helm-charts'; do
    yaml_lists_file "$APPPROJ" "$_repo" || \
        run_cmd _yaml_insert_after "$APPPROJ" \
            '^\s*-\s*https://kyverno\.github\.io/kyverno\s*$' \
            "    - $_repo"
done
_sourcerepos_ok() {
    yaml_lists_file "$APPPROJ" 'https://victoriametrics.github.io/helm-charts' && \
    yaml_lists_file "$APPPROJ" 'https://helm.vector.dev' && \
    yaml_lists_file "$APPPROJ" 'https://grafana.github.io/helm-charts'
}
gate "obs-sourcerepos-en-appproject" _sourcerepos_ok

# grafana y ntfy en `plataforma:` de edge.yaml — la lista de la que
# `bin/aegis-org borde` DERIVA public_hostnames (nadie edita main.tf
# a mano; la lección de ai.__ROOT_DOMAIN__):
EDGE_YAML="$PLATFORM_DIR/edge.yaml"
yaml_lists_file "$EDGE_YAML" grafana || \
    run_cmd _yaml_insert_after "$EDGE_YAML" '^  - jenkins$' '  - grafana'
yaml_lists_file "$EDGE_YAML" ntfy || \
    run_cmd _yaml_insert_after "$EDGE_YAML" '^  - grafana$' '  - ntfy'
_edge_hostnames_ok() {
    yaml_lists_file "$EDGE_YAML" grafana && yaml_lists_file "$EDGE_YAML" ntfy
}
gate "obs-edge-declara-grafana-ntfy" _edge_hostnames_ok

# ── 85.3 render de placeholders de clase-config ────────────────────
# Idempotente; renderiza los __OBS_*__/__AEGIS_PROFILE__ de los
# archivos recién copiados (fase-85 §4.3 — la tabla de derivación por
# $PROFILE vive junto a render_platform_placeholders en common.sh).
# En arranque virgen ya lo hizo la fase 10 y esto es no-op.
render_platform_placeholders

# ── 85.4 SECRETOS (§3, mismo camino que todos: A7/D11) ─────────────
secrets_workdir

# grafana_admin_pass → grafana-admin.enc.yaml (keys admin-user /
# admin-password: el contrato del chart con admin.existingSecret).
# Grafana queda tras Access PERO conserva su login: Access es la
# puerta, no la única cerradura (fase-85 §3).
GRAF_PASS="$(gen_or_restore grafana_admin_pass gen_password_b64)"
GRAF_USER="$(materialize grafana-admin-user admin)"
make_enc_secret grafana-admin observability \
    "$OBS/grafana-admin.enc.yaml" \
    "admin-user=$GRAF_USER" "admin-password=$GRAF_PASS"

# ntfy_puente_token → ntfy-puente-token.enc.yaml: el config scfg
# ENTERO del ntfy-alertmanager (key `config`) — lleva la credencial
# con la que el puente PUBLICA en ntfy, por eso vive en Secret y no
# en ConfigMap (contrato documentado en ntfy-puente.yaml):
PUEN_PASS="$(gen_or_restore ntfy_puente_token gen_password_b64)"
{
    printf 'http-address :8080\n'
    printf 'alert-mode single\n'
    printf 'ntfy {\n'
    printf '    server http://ntfy.observability.svc\n'
    printf '    topic aegis-alertas\n'
    printf '    user puente\n'
    printf '    password %s\n' "$(cat "$PUEN_PASS")"
    printf '}\n'
    printf 'cache {\n'
    printf '    type memory\n'
    printf '}\n'
} > "$SECRETS_TMP/ntfy-puente.scfg"
make_enc_secret ntfy-puente-token observability \
    "$OBS/ntfy-puente-token.enc.yaml" \
    "config=$SECRETS_TMP/ntfy-puente.scfg"

# ntfy_operador_pass: credencial de la app del teléfono. NO va a
# Secret K8s (nadie en el cluster la consume — mismo razonamiento que
# access_st en la fase 25): vive en el store y se muestra al operador
# UNA vez (human_step más abajo, cuando ntfy ya esté vivo). El par
# restore/persist va LITERAL y no vía gen_or_restore porque hace
# falta saber si es NUEVA (solo entonces se muestra):
NTFY_OP_RC=0
OPF="$(restore_secret ntfy_operador_pass)" || NTFY_OP_RC=$?
store_rc_guard "$NTFY_OP_RC" ntfy_operador_pass
NTFY_OPERADOR_NUEVA=false
if (( NTFY_OP_RC != 0 )); then
    OPF="$(gen_password_b64 ntfy_operador_pass)"
    persist_secret ntfy_operador_pass "$OPF"
    NTFY_OPERADOR_NUEVA=true
fi

# entries del generator EN EL MISMO COMMIT que los .enc.yaml (regla
# temporal, corrida #4). La semilla ya las trae como entry REAL de
# lista; el guard estructural + gate cubren la instancia divergida:
GEN_OBS="$OBS/secret-generator.yaml"
yaml_lists_file "$GEN_OBS" grafana-admin.enc.yaml || \
    run_cmd _yaml_insert_after "$GEN_OBS" '^files:$' '  - grafana-admin.enc.yaml'
gate "obs-grafana-admin-en-generator" \
    yaml_lists_file "$GEN_OBS" grafana-admin.enc.yaml
yaml_lists_file "$GEN_OBS" ntfy-puente-token.enc.yaml || \
    run_cmd _yaml_insert_after "$GEN_OBS" '^files:$' '  - ntfy-puente-token.enc.yaml'
gate "obs-ntfy-puente-en-generator" \
    yaml_lists_file "$GEN_OBS" ntfy-puente-token.enc.yaml

# ── hashes bcrypt de ntfy (clase-GENERADO, dueño: esta fase) ───────
# auth-users de ntfy pide `usuario:hash-bcrypt:rol` en el ConfigMap.
# El hash se deriva con htpasswd -B: ya es dependencia dura del init
# (derive_htpasswd_and_regcreds, fase 40; declarada en lib/checks.sh)
# — ni python3-bcrypt ni nada nuevo. -C 10 iguala el costo que usa el
# propio ntfy (`ntfy user hash`); el $2y$ de htpasswd lo acepta el
# bcrypt de Go que ntfy usa (mismo combo documentado para traefik).
# El password JAMÁS por argv: htpasswd -i lo lee de stdin (A27).
_ntfy_hash() {   # <passfile> → hash bcrypt por stdout (y nada más)
    htpasswd -nBi -C 10 x < "$1" | cut -d: -f2 | tr -d '\n'
}
# ¿el hash VIVO en el yaml matchea el password del store? (guard de
# convergencia: re-run sin cambios = no-op; password ROTADO = el hash
# viejo ya no verifica y se reemplaza — sin esto, la receta de
# rotación de aegis-rotate sería un no-op silencioso):
NTFY_YAML="$OBS/ntfy.yaml"
_ntfy_hash_al_dia() {   # <usuario> <passfile>
    # anclado al rol `:user"` de auth-users — sin eso, la entry
    # `usuario:topic:permiso` de auth-access matchea también (lo cazó
    # el harness de fixtures antes de tocar instancia alguna):
    local h
    h="$(grep -oP -- "-\s*\"$1:\K[^:\"]+(?=:user\")" "$NTFY_YAML" | head -1)"
    [[ -n "$h" && "$h" != __OBS_* ]] || return 1
    printf '%s:%s\n' "$1" "$h" > "$SECRETS_TMP/htcheck-$1"
    htpasswd -vi "$SECRETS_TMP/htcheck-$1" "$1" < "$2" >/dev/null 2>&1
}
_ntfy_hash_reemplaza() {   # <usuario> <hashfile> — rotación: pisa el hash viejo
    python3 - "$NTFY_YAML" "$1" "$2" <<'EOF'
import re, sys, yaml
p, user, hpath = sys.argv[1], sys.argv[2], sys.argv[3]
h = open(hpath).read().strip()
text = open(p).read()
# anclado al rol `:user"` de auth-users: la entry de auth-access
# (`usuario:topic:permiso`) también empieza igual y NO debe tocarse:
pat = re.compile(r'(- "%s:)[^:"]+(:user")' % re.escape(user))
out, n = pat.subn(lambda m: m.group(1) + h + m.group(2), text)
if n != 1:
    sys.exit(f"hash de {user}: {n} ocurrencias (se exige EXACTAMENTE 1) en {p}")
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"el YAML resultante de {p} NO parsea ({e}) — queda INTACTO")
open(p, "w").write(out)
EOF
}
NTFY_CONF_CAMBIO=false
_ntfy_usuario_convergido() {   # <usuario> <passfile> <placeholder>
    local user="$1" passfile="$2" ph="$3"
    if placeholder_pending "$NTFY_YAML" "$ph"; then
        _ntfy_hash "$passfile" > "$SECRETS_TMP/hash-$user"
        run_cmd inject_placeholder "$NTFY_YAML" "$ph" "$SECRETS_TMP/hash-$user"
        NTFY_CONF_CAMBIO=true
    elif ! _ntfy_hash_al_dia "$user" "$passfile"; then
        log_warn "hash de '$user' en ntfy.yaml NO matchea el password del store (¿rotación?) — se re-deriva y reemplaza"
        _ntfy_hash "$passfile" > "$SECRETS_TMP/hash-$user"
        run_cmd _ntfy_hash_reemplaza "$user" "$SECRETS_TMP/hash-$user"
        NTFY_CONF_CAMBIO=true
    fi
}
_ntfy_usuario_convergido operador "$OPF"       __OBS_NTFY_OPERADOR_HASH__
_ntfy_usuario_convergido puente   "$PUEN_PASS" __OBS_NTFY_PUENTE_HASH__
# gate del RESULTADO (regla de la familia H4): el hash vivo VERIFICA
# contra el password del store — no solo "el placeholder murió":
gate "obs-ntfy-hash-operador" _ntfy_hash_al_dia operador "$OPF"
gate "obs-ntfy-hash-puente"   _ntfy_hash_al_dia puente "$PUEN_PASS"

# ── __OBS_CA_PEM__: el CA VIVO al ConfigMap de blackbox ────────────
# Mismo patrón que __AEGIS_CA_PEM__ en la fase 80 (el CA no existe
# hasta que cert-manager lo emite en la 35). blackbox valida la
# cadena CONTRA este CA — jamás insecure_skip_verify (el -k que P2.4
# desterró): un probe con -k daría expiry igual pero dejaría pasar un
# cert EQUIVOCADO en verde.
CAY="$OBS/configmap-aegis-ca.yaml"
if placeholder_pending "$CAY" __OBS_CA_PEM__; then
    kubectl -n cert-manager get secret aegis-internal-ca \
        -o jsonpath='{.data.ca\.crt}' | base64 -d \
        > "$SECRETS_TMP/obs-aegis-ca.pem"
    run_cmd inject_placeholder "$CAY" __OBS_CA_PEM__ "$SECRETS_TMP/obs-aegis-ca.pem"
fi
gate "obs-ca-inyectado" bash -c \
    "grep -q 'BEGIN CERTIFICATE' '$CAY' && ! grep -q '__OBS_CA_PEM__' '$CAY'"

# commit + push: ArgoCD lee del remoto, no del disco. Sin || true
# (clase F): staged vacío = no-op legítimo, fallo real mata acá.
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(observabilidad): apps + secretos cifrados + CA y hashes inyectados"
git_push_verified "$PLATFORM_DIR"

# ── 85.5 AppProjects por kubectl (clase C1, como en la fase 35) ────
# Sin los sourceRepos nuevos, el primer sync de un chart moriría con
# "not permitted". Infra de bootstrap imperativa, fuera del root:
run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/bootstrap/appprojects.yaml"
gate "obs-sourcerepos-aplicados" bash -c \
  "kubectl -n argocd get appproject aegis-platform -o json \
     | jq -e '.spec.sourceRepos | contains([\"https://victoriametrics.github.io/helm-charts\",\"https://helm.vector.dev\",\"https://grafana.github.io/helm-charts\"])' >/dev/null"

# ── 85.6 el borde: hostnames DERIVADOS + tofu apply ────────────────
# `aegis-org borde` deriva public_hostnames de edge.yaml + contratos
# (nadie edita main.tf a mano); el apply crea CNAMEs, ingress del
# túnel y la Access App de grafana (grafana.tf). El gate de RESULTADO
# son los dos gates de borde de §8 al final; acá solo se verifica la
# derivación (barato y con causa clara si edge.yaml divergió):
run_cmd bash -c "cd '$PLATFORM_DIR' && bin/aegis-org borde"
gate "obs-borde-derivado" bash -c \
  "grep -E 'public_hostnames *= *\[' '$TUNNEL_ENV/main.tf' | grep -q '\"grafana\"' \
   && grep -E 'public_hostnames *= *\[' '$TUNNEL_ENV/main.tf' | grep -q '\"ntfy\"'"
run_cmd "$TOFU" -chdir="$TUNNEL_ENV" apply -auto-approve || \
    die "tofu apply del borde FALLÓ — un apply parcial deja CNAMEs/ingress envenenados; revisar el plan a mano y re-correr la fase"
# el tfstate a 600 apenas se escribe (fase 25 / fix #82 — el .backup
# quedaba 664 con el token del túnel EN CLARO):
for f in "$TUNNEL_ENV"/terraform.tfstate "$TUNNEL_ENV"/terraform.tfstate.backup; do
    [[ -f "$f" ]] && chmod 600 "$f"
done
# El enc.json re-cifrado POST-apply se commitea ACÁ y no después: el
# wrapper avisa «COMMITEALO» y tiene razón — sin este commit el state
# bueno queda huérfano en el working tree, el siguiente
# platform_repo_sync muere por árbol sucio, y tarde o temprano alguien
# lo descarta y la verdad del borde RETROCEDE (2026-08-21: tres
# applies midiendo contra un enc.json 9 días viejo).
git_commit_if_changes "$PLATFORM_DIR" \
    "chore(borde): state del túnel re-cifrado post-apply (fase 85)" \
    tofu/envs/cloudflare-tunnel/terraform.tfstate.enc.json

# ── 85.7 ENCHUFES ≤3 líneas en los observados (hooks.md / §7) ──────
# En la semilla van de fábrica; acá se agregan a la instancia viva
# con guard ESTRUCTURAL (parse YAML, no grep de mención) y escritura
# que valida el resultado antes de tocar el archivo. En fresh: no-op.

# (1) cloudflared: --metrics 0.0.0.0:2000 + containerPort.
CFD="$B/ingress/cloudflare-tunnel/cloudflared.yaml"
_cloudflared_metricas_ok() {
    python3 - "$CFD" <<'EOF'
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if d and d.get("kind") == "Deployment":
        for c in d["spec"]["template"]["spec"]["containers"]:
            if c.get("name") == "cloudflared" and "--metrics" in (c.get("args") or []):
                sys.exit(0)
sys.exit(1)
EOF
}
_enchufar_cloudflared() {
    python3 - "$CFD" <<'EOF'
import sys, yaml
p = sys.argv[1]
text = open(p).read()
viejo = 'args: ["tunnel", "--no-autoupdate", "run"]'
nuevo = ('args: ["tunnel", "--no-autoupdate", "--metrics", "0.0.0.0:2000", "run"]\n'
         '          ports:\n'
         '            - {name: metrics, containerPort: 2000}')
if text.count(viejo) != 1:
    sys.exit(f"cloudflared.yaml: {text.count(viejo)} ocurrencias del args esperado "
             f"(se exige 1) — el archivo divergió, enchufar a mano (fase-85 §7)")
out = text.replace(viejo, nuevo)
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"el YAML resultante NO parsea ({e}) — {p} queda INTACTO")
open(p, "w").write(out)
EOF
}
_cloudflared_metricas_ok || run_cmd _enchufar_cloudflared
gate "obs-enchufe-cloudflared" _cloudflared_metricas_ok

# (2) Jenkins: plugin `prometheus` en installPlugins (expone
# /prometheus sin API key; `metrics` a secas exige clave por query
# param — hostil a scrape. hooks.md):
JVALS="$B/platform/jenkins/values.yaml"
yaml_lists_file "$JVALS" prometheus || \
    run_cmd _yaml_insert_after "$JVALS" '^    - job-dsl$' '    - prometheus'
gate "obs-enchufe-jenkins-plugin" yaml_lists_file "$JVALS" prometheus

# (3) registry: bloque debug con prometheus en el ConfigMap + puerto
# 5001 en el Service (listener de debug SEPARADO del público):
REGY="$B/registry-system/registry.yaml"
_registry_metricas_ok() {
    python3 - "$REGY" <<'EOF'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
cfg = next((d for d in docs if d.get("kind") == "ConfigMap"
            and d["metadata"]["name"] == "registry-config"), None)
svc = next((d for d in docs if d.get("kind") == "Service"
            and d["metadata"]["name"] == "registry"), None)
ok = False
if cfg:
    inner = yaml.safe_load(cfg["data"]["config.yml"])
    ok = bool(((inner.get("http") or {}).get("debug") or {})
              .get("prometheus", {}).get("enabled"))
ok = ok and svc is not None and \
     any(p.get("port") == 5001 for p in svc["spec"]["ports"])
sys.exit(0 if ok else 1)
EOF
}
_enchufar_registry() {
    python3 - "$REGY" <<'EOF'
import sys, yaml
p = sys.argv[1]
text = open(p).read()
v_cfg = ("      tls:\n"
         "        certificate: /certs/tls.crt\n"
         "        key: /certs/tls.key\n")
n_cfg = v_cfg + ("      debug:\n"
                 "        addr: :5001\n"
                 "        prometheus: {enabled: true}\n")
v_svc = "  ports: [{port: 5000, targetPort: 5000}]"
n_svc = ("  ports:\n"
         "    - {name: registry, port: 5000, targetPort: 5000}\n"
         "    - {name: metrics, port: 5001, targetPort: 5001}")
if text.count(v_cfg) != 1 or text.count(v_svc) != 1:
    sys.exit(f"registry.yaml sin la forma esperada para el enchufe "
             f"(cfg={text.count(v_cfg)} svc={text.count(v_svc)}, se exige 1 y 1) "
             f"— el archivo divergió, enchufar a mano (fase-85 §7)")
out = text.replace(v_cfg, n_cfg).replace(v_svc, n_svc)
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"el YAML resultante NO parsea ({e}) — {p} queda INTACTO")
open(p, "w").write(out)
EOF
}
REGISTRY_ENCHUFADO_ESTA_CORRIDA=false
if ! _registry_metricas_ok; then
    run_cmd _enchufar_registry
    # clase D (regla de oro): config de pod vivo ⇒ restart o checksum.
    # El ConfigMap nuevo NO reinicia al registry solo — se anota para
    # el rollout restart tras el re-sync (85.10):
    REGISTRY_ENCHUFADO_ESTA_CORRIDA=true
fi
gate "obs-enchufe-registry" _registry_metricas_ok

# (4) netpols default-deny que TAPARÍAN la cañería (una entry por
# archivo; sin esto, up==0 con todo «sano» — un agujero de scrape
# indistinguible de un incidente, en el perfil donde los agujeros
# son rutina):
_netpol_permite_observabilidad() {   # <netpol.yaml>
    python3 - "$1" <<'EOF'
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if not d:
        continue
    for r in (d.get("spec", {}).get("ingress") or []):
        for f in (r.get("from") or []):
            sel = (f.get("namespaceSelector") or {}).get("matchLabels") or {}
            if sel.get("kubernetes.io/metadata.name") == "observability":
                sys.exit(0)
sys.exit(1)
EOF
}
_netpol_abre_a_observabilidad() {   # <netpol.yaml> <puerto>...
    python3 - "$@" <<'EOF'
import sys, yaml
p, puertos = sys.argv[1], sys.argv[2:]
text = open(p).read()
bloque = ['    - from:',
          '        - namespaceSelector:',
          '            matchLabels: {kubernetes.io/metadata.name: observability}',
          '      ports:'] + \
         ['        - {protocol: TCP, port: %s}' % pt for pt in puertos]
out = text.rstrip("\n") + "\n" + "\n".join(bloque) + "\n"
try:
    docs = list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"el YAML resultante NO parsea ({e}) — {p} queda INTACTO")
# el efecto, no la escritura: el append tiene que haber quedado
# DENTRO de la lista ingress de una policy (si el archivo divergió y
# no termina en esa lista, mejor morir acá que un netpol roto vivo):
ok = any((f.get("namespaceSelector") or {}).get("matchLabels", {})
         .get("kubernetes.io/metadata.name") == "observability"
         for d in docs if d
         for r in (d.get("spec", {}).get("ingress") or [])
         for f in (r.get("from") or []))
if not ok:
    sys.exit(f"el append a {p} no quedó dentro de ingress (¿archivo divergido?) — enchufar a mano")
open(p, "w").write(out)
EOF
}
NP_JENKINS="$B/platform/jenkins-secrets/netpol.yaml"
NP_ARGOCD="$B/platform/argocd-secrets/netpol.yaml"
NP_TRIVY="$B/trivy-system/netpol.yaml"
_netpol_permite_observabilidad "$NP_JENKINS" || \
    run_cmd _netpol_abre_a_observabilidad "$NP_JENKINS" 8080
_netpol_permite_observabilidad "$NP_ARGOCD" || \
    run_cmd _netpol_abre_a_observabilidad "$NP_ARGOCD" 8082 8083 8084
_netpol_permite_observabilidad "$NP_TRIVY" || \
    run_cmd _netpol_abre_a_observabilidad "$NP_TRIVY" 4954
gate "obs-netpol-jenkins" _netpol_permite_observabilidad "$NP_JENKINS"
gate "obs-netpol-argocd"  _netpol_permite_observabilidad "$NP_ARGOCD"
gate "obs-netpol-trivy"   _netpol_permite_observabilidad "$NP_TRIVY"

# commit de enchufes + tfstate recifrado del borde (85.6) + push:
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(observabilidad): enchufes de metricas (cloudflared/jenkins/registry) + netpols + borde"
git_push_verified "$PLATFORM_DIR"

# ── 85.8 root MANUAL siempre (ADR-0012): las Apps nuevas nacen acá ─
argo_sync root 300

# ── 85.9 syncs en ORDEN: productores antes que consumidores (D5) ───
# base primero (namespace + Secrets + crudos: sin ns no hay dónde,
# sin Secret grafana no arranca), luego stores, luego colectores,
# luego vmalert, último grafana:
argo_sync observability-base 600
# F-B #15: Synced cuenta SOLO a la revisión RECIÉN pusheada (el HEAD
# es el del push de 85.7 — nada commitea entre medio):
argo_secrets_gate observability-base 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
# A7: validación post-sync SIEMPRE — Synced+Healthy no garantiza los
# Secrets si el generator no corrió:
gate "obs-secretos-vivos" poll 180 5 bash -c \
  "kubectl -n observability get secret grafana-admin ntfy-puente-token >/dev/null 2>&1"
argo_sync vmsingle 600
argo_sync vlogs 600
argo_sync vlogs-eventos 600
argo_sync vmagent 600
argo_sync vector 600
argo_sync vmalert 600
argo_sync grafana 900

# ── 85.10 re-sync de los observados enchufados ─────────────────────
# (los netpol tocados viajan en sus apps: jenkins-secrets /
#  argocd-secrets / trivy-system)
argo_sync cloudflare-tunnel 600
gate "obs-cloudflared-convergido" wait_rollout infra-edge deploy/cloudflared 600
argo_sync jenkins-secrets
argo_sync argocd-secrets
argo_sync trivy-system
# el de jenkins REINICIA el controller (plugin nuevo) — precio de una
# vez; el gate de Jenkins de la fase 50 no se re-corre, pero la
# convergencia ANTES de medir sí (familia nº1):
argo_sync jenkins 900
gate "obs-jenkins-convergido" wait_rollout jenkins-system sts/jenkins 900
argo_sync registry 600
# Converger por EFECTO, no por historia. La primera versión reiniciaba
# solo si el ConfigMap cambió en ESTA corrida
# ($REGISTRY_ENCHUFADO_ESTA_CORRIDA) — y el tercer encendido
# (2026-08-21) encontró el hueco: el enchufe había entrado en una
# corrida ANTERIOR, el pod llevaba 12 días con la config vieja, el
# rollout que el gate esperaba nunca existió y wait_rollout pasó en
# vacío — obs-metricas-fluyen murió 15 minutos después señalando
# registry:5001. Es B11 en carne propia: config renovada, pod rancio.
# La condición honesta: ¿el pod SIRVE lo que el ConfigMap declara?
# Venga el cambio de esta corrida, de la semana pasada o de una mano.
_registry_sirve_metricas() {
    # Por el SERVICE y no por items[0] del namespace (check 72): el
    # Service solo enruta a pods Ready, y durante un Recreate el [0]
    # de la lista podía ser el pod agonizante. Si el pod Ready no
    # escucha :5001, el curl al Service falla igual — que es lo que
    # este guard quiere saber.
    local ip
    ip="$(kubectl -n registry-system get svc registry \
            -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
    [[ -n "$ip" && "$ip" != "None" ]] || return 1
    curl -fsS --max-time 5 "http://$ip:5001/metrics" >/dev/null 2>&1
}
if kubectl -n registry-system get cm registry-config -o jsonpath='{.data.config\.yml}' 2>/dev/null \
        | grep -q 'debug:' && ! _registry_sirve_metricas; then
    log_info "el ConfigMap declara métricas y el pod no las sirve — rollout restart (B11)"
    run_cmd kubectl -n registry-system rollout restart deploy/registry
fi
gate "obs-registry-convergido" wait_rollout registry-system deploy/registry 600

# ── 85.11 ingesta del histórico del init a vlogs-eventos ───────────
# gates.jsonl (P2.13) → jsonline con _stream source=aegis-init. NO es
# best-effort: acá el destino DEBE existir — si falla, falla la fase
# (a diferencia del push por gate futuro de hooks.md, que corre antes
# de que exista el destino). El count se captura ANTES: los gates de
# abajo apendean líneas nuevas y el ≥ sigue valiendo.
GATES_JSONL="$AEGIS_STATE_DIR/gates.jsonl"
N_GATES=0
[[ -s "$GATES_JSONL" ]] && N_GATES="$(wc -l < "$GATES_JSONL")"
# IP alcanzable desde el HOST para un Service del stack. Los charts de
# VictoriaMetrics/Logs crean Services HEADLESS para sus StatefulSets:
# jsonpath de clusterIP devuelve el STRING "None", curl intenta
# http://None:9428, y retry_net lo lee como fallo de red — así murió
# el encendido del 2026-08-21, con 15 gates en verde arriba. Para un
# headless se va al primer endpoint (pod IP): en k3s single-node las
# pod IPs son routables desde el host igual que las ClusterIP. Dentro
# del cluster nada de esto aplica (el DNS del headless resuelve solo;
# el CronJob trivy-db-age usa el nombre y está bien así).
_svc_ip() {   # <svc> → IP alcanzable, o vacío (y el caller decide)
    local ip
    ip="$(kubectl -n observability get svc "$1" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
    if [[ -z "$ip" || "$ip" == "None" ]]; then
        ip="$(kubectl -n observability get endpoints "$1" \
                -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)"
    fi
    [[ -n "$ip" && "$ip" != "None" ]] && printf '%s' "$ip"
}
VLE_IP="$(_svc_ip vlogs-eventos)" \
    || die "vlogs-eventos sin IP alcanzable (¿pod sin Ready? kubectl -n observability get endpoints vlogs-eventos)"
_ingesta_historico() {
    # el campo source se agrega con jq (byte-honesto y sin depender de
    # extra_fields del servidor); ts ISO del propio registro = _time.
    # El Content-Type NO es decorativo: sin header, curl declara
    # x-www-form-urlencoded y VictoriaLogs DESCARTA el body entero con
    # HTTP 200 y cero filas — sin drop, sin log, sin queja (medido
    # 2026-08-21 en el segundo encendido: la request contaba, los bytes
    # no). El gate obs-eventos-ingestados existe para cazar exactamente
    # esta clase de éxito falso, pero mejor no dárselo de comer:
    jq -c '. + {source: "aegis-init"}' "$GATES_JSONL" \
      | curl -fsS --max-time 60 -H 'Content-Type: application/stream+json' \
          --data-binary @- \
          "http://$VLE_IP:9428/insert/jsonline?_time_field=ts&_msg_field=gate&_stream_fields=source"
}
if (( N_GATES > 0 )); then
    # Convergencia del re-run: la ingesta postea el archivo ENTERO, y
    # gates.jsonl es append-only — re-correr la fase sin este guard
    # duplicaría TODA la historia en el store de 1 año, una copia por
    # corrida. Si el stream ya tiene al menos tantas filas como el
    # archivo, la historia ya está (el ≥ y no ==: los gates de esta
    # corrida apendearon líneas después de la última ingesta, y las
    # corridas futuras las traerán):
    N_YA="$(curl -fsS --max-time 20 "http://$VLE_IP:9428/select/logsql/query" \
              --data-urlencode 'query={source="aegis-init"} | stats count() as filas' 2>/dev/null \
            | jq -r '.filas // "0"' | head -n1)"
    [[ "$N_YA" =~ ^[0-9]+$ ]] || N_YA=0
    if (( N_YA >= N_GATES )); then
        log_info "histórico ya en vlogs-eventos ($N_YA filas >= $N_GATES del archivo): no se re-ingesta"
    else
        run_cmd retry_net 3 _ingesta_historico || \
            die "ingesta de gates.jsonl a vlogs-eventos FALLÓ — el endpoint DEBE existir (fase-85 §6.11); revisar la App vlogs-eventos"
        log_ok "histórico ingestado: $N_GATES líneas de gates.jsonl → vlogs-eventos (la historia sobrevive a --reset-state)"
    fi
else
    log_warn "sin gates.jsonl que ingestar (¿--reset-state recién?) — lo ya ingestado en corridas previas SOBREVIVE en vlogs-eventos"
fi

# ── 85.12 GATES FINALES (§8): medir el EFECTO, no el deployment ────
VM_IP="$(_svc_ip vmsingle)"       || die "vmsingle sin IP alcanzable"
VLOGS_IP="$(_svc_ip vlogs)"       || die "vlogs sin IP alcanzable"
VMALERT_IP="$(_svc_ip vmalert)"   || die "vmalert sin IP alcanzable"
GRAFANA_IP="$(_svc_ip grafana)"   || die "grafana sin IP alcanzable"
_promql() {   # <query> → valor del primer resultado (o 0)
    curl -fsS --max-time 15 "http://$VM_IP:8428/api/v1/query" \
        --data-urlencode "query=$1" 2>/dev/null \
      | jq -r '.data.result[0].value[1] // "0"'
}
_logsql_count() {   # <ip> <query LogsQL con `stats count() as filas`>
    curl -fsS --max-time 20 "http://$1:9428/select/logsql/query" \
        --data-urlencode "query=$2" 2>/dev/null \
      | jq -r '.filas // "0"' | head -n1
}

# (1) obs-metricas-fluyen: vmagent scrapea DE VERDAD. Piso esperado:
# 13 targets estáticos (vmagent + 8 del stack + jenkins + registry +
# 2 sondas blackbox) + cadvisor(1) + argocd(3) + cert-manager(1) +
# kyverno(≥1) + traefik(1) + cloudflared(1) ≈ 21; el piso queda en 18
# (margen para réplicas variables de kyverno) Y ADEMÁS cero up==0 —
# el target caído por netpol se ve ACÁ y no 3 días después:
OBS_TARGETS_MIN=18
_metricas_fluyen() {
    local arriba caidos
    arriba="$(_promql 'count(up==1)')"
    caidos="$(_promql 'count(up==0)')"
    [[ "$arriba" =~ ^[0-9]+$ && "$caidos" =~ ^[0-9]+$ ]] || return 1
    (( arriba >= OBS_TARGETS_MIN )) || return 1
    (( caidos == 0 ))
}
_diag_up_caidos() {
    printf 'up==1: %s (esperados >= %s); targets con up==0:\n' \
        "$(_promql 'count(up==1)')" "$OBS_TARGETS_MIN"
    curl -fsS --max-time 15 "http://$VM_IP:8428/api/v1/query" \
        --data-urlencode 'query=up==0' 2>/dev/null \
      | jq -r '.data.result[]?.metric | "  up==0: job=\(.job) instance=\(.instance)"'
}
gate_diag "obs-metricas-fluyen" '_diag_up_caidos' \
    poll 900 15 _metricas_fluyen

# (2) obs-logs-fluyen: Vector → vlogs de punta a punta (líneas con ts
# reciente — Vector estampa su propio timestamp, §9 reloj WSL2):
_logs_fluyen() {
    local filas
    filas="$(_logsql_count "$VLOGS_IP" '_time:15m | stats count() as filas')"
    [[ "$filas" =~ ^[0-9]+$ ]] && (( filas > 0 ))
}
gate_diag "obs-logs-fluyen" \
    'kubectl -n observability get pods -l app.kubernetes.io/name=vector 2>/dev/null; kubectl -n observability logs daemonset/vector --tail=15 2>/dev/null' \
    poll 600 15 _logs_fluyen

# (3) obs-eventos-ingestados: la ingesta de 85.11 ATERRIZÓ (Synced no
# prueba datos — misma lección que F-B):
_eventos_ingestados() {
    local filas
    filas="$(_logsql_count "$VLE_IP" '_stream:{source="aegis-init"} | stats count() as filas')"
    [[ "$filas" =~ ^[0-9]+$ ]] && (( filas >= N_GATES ))
}
gate_diag "obs-eventos-ingestados" \
    'printf "esperadas >= %s lineas con _stream source=aegis-init\n" "$N_GATES"' \
    poll 300 10 _eventos_ingestados

# (4) obs-cert-servido-medido: B11 DE VERDAD — blackbox mide lo
# SERVIDO por el registry con handshake real contra el CA; >0 =
# cadena validada (un -k daría expiry igual con un cert EQUIVOCADO):
_cert_servido() {
    curl -fsS --max-time 15 "http://$VM_IP:8428/api/v1/query" \
        --data-urlencode 'query=probe_ssl_earliest_cert_expiry{instance=~"registry.*"} > 0' 2>/dev/null \
      | jq -e '.data.result | length > 0' >/dev/null
}
gate_diag "obs-cert-servido-medido" \
    '_promql "probe_success{job=\"blackbox-registry\"}"; kubectl -n observability logs deploy/blackbox --tail=10 2>/dev/null' \
    poll 600 15 _cert_servido

# (5) obs-deadman-firing: la regla evalúa (vector(1) SIEMPRE firing —
# su valor es su AUSENCIA en el teléfono):
_deadman_firing() {
    curl -fsS --max-time 15 "http://$VMALERT_IP:8880/api/v1/alerts" 2>/dev/null \
      | jq -e '.data.alerts[]? | select((.name // .alertname) == "DeadmanAegis" and .state == "firing")' \
        >/dev/null
}
gate_diag "obs-deadman-firing" \
    'curl -fsS --max-time 15 "http://$VMALERT_IP:8880/api/v1/alerts" 2>/dev/null | jq . 2>/dev/null | head -n 40' \
    poll 600 15 _deadman_firing

# ── la credencial del teléfono, mostrada UNA vez (§3) ──────────────
# Recién ACÁ y no al acuñarla: ntfy ya está vivo y el operador puede
# suscribir la app en el momento. W-01: el valor NO pasa por este
# pane (tmux/script/transcripts lo graban) — va a tmpfs y se lee
# desde OTRA terminal, como la ceremonia age. Sin QR: generarlo
# exigiría una dependencia nueva (qrencode); la app suscribe por URL.
if [[ "$NTFY_OPERADOR_NUEVA" == "true" ]]; then
    NTFY_OP_SHM="/dev/shm/aegis-ntfy-operador-$$"
    ( umask 077; run_cmd install -m 600 "$OPF" "$NTFY_OP_SHM" )
    human_step "Credencial de ntfy para la app del teléfono (UNA vez)" \
        "1. Instalá la app ntfy (F-Droid / Play / App Store)." \
        "2. Suscribite al topic:  servidor https://ntfy.$ROOT_DOMAIN — topic aegis-alertas" \
        "3. Usuario: operador. La password se lee desde OTRA terminal" \
        "   (NO este pane):  cat $NTFY_OP_SHM" \
        "4. En unos minutos la app debe mostrar el heartbeat DeadmanAegis." \
        "   (si perdés la password: sops -d .state-secrets/ntfy_operador_pass.enc)" \
        "5. Al continuar, el init borra la copia de /dev/shm."
    run_cmd rm -f "$NTFY_OP_SHM"
else
    log_info "ntfy_operador_pass ya estaba en el store — no se re-muestra (recuperable con la age key)"
fi

# (6) obs-cadena-alerta-canal — EL gate de la fase: el heartbeat
# LLEGÓ al topic (regla → Alertmanager → puente → ntfy, completa).
# Vigilar al vigía se MIDE en el nacimiento, no se declara
# (Enfermedad E). Poll por el canal PÚBLICO (el mismo que usa el
# teléfono) con la credencial del operador — password por netrc en
# tmpfs, jamás argv (A27):
( umask 077; printf 'machine ntfy.%s login operador password %s\n' \
    "$ROOT_DOMAIN" "$(cat "$OPF")" > "$SECRETS_TMP/ntfy-operador.netrc" )
_alerta_llego_a_ntfy() {
    curl -fsS --max-time 30 --netrc-file "$SECRETS_TMP/ntfy-operador.netrc" \
        "https://ntfy.$ROOT_DOMAIN/aegis-alertas/json?poll=1" 2>/dev/null \
      | grep -qiE 'DeadmanAegis|latido'
}
gate_diag "obs-cadena-alerta-canal" \
    'kubectl -n observability logs deploy/ntfy-puente --tail=15 2>/dev/null; kubectl -n observability logs deploy/alertmanager --tail=15 2>/dev/null; kubectl -n observability logs deploy/ntfy --tail=10 2>/dev/null' \
    poll 900 20 _alerta_llego_a_ntfy

# (7) obs-grafana-provisionado: el provisioning desde git aterrizó —
# 0 datasources con pod Healthy es exactamente el fallo que «Healthy»
# no ve. In-cluster vía Service; credencial por netrc (A27):
( umask 077; printf 'machine %s login admin password %s\n' \
    "$GRAFANA_IP" "$(cat "$GRAF_PASS")" > "$SECRETS_TMP/grafana-admin.netrc" )
_grafana_provisionado() {
    curl -fsS --max-time 15 "http://$GRAFANA_IP:80/api/health" 2>/dev/null \
      | jq -e '.database == "ok"' >/dev/null || return 1
    local n
    n="$(curl -fsS --max-time 15 --netrc-file "$SECRETS_TMP/grafana-admin.netrc" \
        "http://$GRAFANA_IP:80/api/datasources" 2>/dev/null | jq -r 'length' 2>/dev/null)"
    [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 3 ))
}
gate_diag "obs-grafana-provisionado" \
    'kubectl -n observability get pods -l app.kubernetes.io/name=grafana 2>/dev/null; kubectl -n observability logs deploy/grafana --tail=20 2>/dev/null' \
    poll 600 15 _grafana_provisionado

# (8) obs-grafana-tras-access: «origen contestó» ≠ «Access
# interceptó» — jamás un curl desnudo contra hostname protegido
# (check 90). 200/302 del ORIGEN (grafana redirige a /login sin
# sesión); el redirect a cloudflareaccess.com es fallo del helper:
gate_diag "obs-grafana-tras-access" \
    'kubectl -n infra-edge logs deploy/cloudflared --tail=15 2>/dev/null' \
    poll 600 10 edge_origen_responde "https://grafana.$ROOT_DOMAIN" '^(200|30[12])$'

# (9) obs-ntfy-publico-responde: el canal llega al teléfono Y el
# deny-all está activo — publicar sin credencial debe dar 403 (un
# ntfy abierto sería spam-relay con nuestro dominio). curl desnudo A
# PROPÓSITO: ntfy va sin Access (la app no presenta service token):
_ntfy_publico_ok() {
    local salud publica
    salud="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
        "https://ntfy.$ROOT_DOMAIN/v1/health" 2>/dev/null)" || return 1
    [[ "$salud" == "200" ]] || return 1
    publica="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
        -d 'probe sin credencial (gate obs-ntfy-publico-responde)' \
        "https://ntfy.$ROOT_DOMAIN/aegis-alertas" 2>/dev/null)" || return 1
    [[ "$publica" == "403" ]]
}
gate_diag "obs-ntfy-publico-responde" \
    'kubectl -n observability logs deploy/ntfy --tail=15 2>/dev/null; kubectl -n infra-edge logs deploy/cloudflared --tail=10 2>/dev/null' \
    poll 600 15 _ntfy_publico_ok

log_ok "OBSERVABILIDAD COMPLETA: métricas/logs/eventos fluyendo, B11 \
midiendo lo SERVIDO, deadman → Alertmanager → puente → ntfy probado \
de punta a punta, Grafana provisionado 100% desde git tras Access."
