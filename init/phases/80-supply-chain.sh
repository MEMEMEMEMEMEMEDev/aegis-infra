#!/usr/bin/env bash
# FASE 80 — supply-chain: Trivy → cosign (store, D11) → Kyverno con
# el ORDEN COMO MECANISMO (D5): kyverno-policies (Enforce) es lo
# ÚLTIMO que se habilita, después de que exista la primera imagen
# FIRMADA — en fresh, Enforce antes de la primera firma rechazaría
# al propio tenant (H-7, ahora codificado).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 reporte in-VM #14: esta fase MUTA el repo de plataforma — el
# clone local puede estar detras del remoto (fix manual del operador
# en GitHub durante un retome). Sincronizar ANTES de tocar nada:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

# argo_sync viene de lib/common.sh (bug C corrida #8: las defs
# locales esperaban solo health — carrera con operationState en
# re-runs; la canónica espera la fase TERMINAL de la operación).

# ── 80.1 Trivy server (el scan ya estaba en el Jenkinsfile; hasta
#     ahora los builds corrieron con el stage en modo tolerante) ───
argo_sync trivy-system
argo_sync trivy-server 600
# P1.8 auditoría: delete previo por intento — el --rm + retry se
# auto-anulaba si el attach vencía (pod huérfano → AlreadyExists).
# RACE del netpol (corrida integración 2026-07-23, W-07 iter2): con la
# default-deny de trivy-system, un pod-probe RECIÉN creado curl-ea ANTES
# de que kube-router programe su IP en el ipset intra-ns → connection
# refused (exit 7). El retry EXTERNO no ayuda: crea un pod NUEVO cada vez,
# que vuelve a perder la carrera. Fix: reintentar DENTRO del mismo pod
# (así kube-router lo programa durante el 1er sleep). Ver
# feedback-netpol-enforcement-vs-manifest: el manifiesto es correcto, el
# enforcement (ipset) tiene lag al crear el pod. Los clientes reales (build
# pods) NO sufren esto: viven minutos antes de escanear.
gate "trivy-responde" retry_net 3 bash -c \
  "kubectl -n trivy-system delete pod trivy-probe --ignore-not-found --now >/dev/null 2>&1; \
   kubectl -n trivy-system run trivy-probe --rm -i --restart=Never \
     --image=alpine/curl -- \
     sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12; do \
       curl -fsS --max-time 5 http://trivy.trivy-system.svc.cluster.local:4954/healthz && exit 0; \
       sleep 3; done; exit 1' \
     >/dev/null"

# ── 80.2 cosign: autoridad de firma SIN ceremonia (D11) ────────────
# La ceremonia manual desapareció: password y keypair van al store
# cifrado — recuperables con la age key, que es EL único
# irreducible. gen_or_restore hace el re-run idempotente (bug 6:
# regenerar el keypair invalidaría las firmas ya emitidas).
secrets_workdir
COSIGN_PASS="$(gen_or_restore cosign_pass gen_password_b64)"
# corrida #11 (clase): "no descifra" ≠ "no existe" — regenerar el
# keypair ante un sops mudo invalidaría TODAS las firmas emitidas.
# rc 2 = parar (store_rc_guard); rc 1 = no existe, generar es legal.
# Sin 2>&1: el error de sops debe VERSE, no tragarse:
RC=0
restore_secret cosign_key cosign.key >/dev/null || RC=$?
store_rc_guard "$RC" cosign_key
if (( RC != 0 )); then
    gen_cosign_keypair "$SECRETS_TMP/cosign_pass"
    persist_secret cosign_key "$SECRETS_TMP/cosign.key"
    persist_secret cosign_pub "$SECRETS_TMP/cosign.pub"
else
    RC=0
    restore_secret cosign_pub cosign.pub >/dev/null || RC=$?
    store_rc_guard "$RC" cosign_pub
    (( RC == 0 )) || die "store inconsistente: cosign_key existe pero falta cosign_pub — no se regenera solo (invalidaría firmas); revisar .state-secrets/"
    log_info "cosign keypair restaurado del store (firmas previas siguen válidas)"
fi
gate "cosign-material-completo" bash -c \
    "test -s '$SECRETS_TMP/cosign.key' && test -s '$SECRETS_TMP/cosign.pub'"

make_enc_secret cosign-signing-key jenkins-system \
    "$PLATFORM_DIR/k8s/base/platform/jenkins-secrets/secret-cosign-signing-key.enc.yaml" \
    "cosign.key=$SECRETS_TMP/cosign.key" \
    "cosign.password=$SECRETS_TMP/cosign_pass"
# la PÚBLICA es T1 → al repo en claro + inline en la policy:
run_cmd cp "$SECRETS_TMP/cosign.pub" \
    "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub"
# inyectar la pub en la ClusterPolicy (placeholder __COSIGN_PUB__).
# CR-1 corrida #14: el replace() global volcaba el PEM TAMBIÉN en el
# comentario del header que mencionaba el placeholder → YAML top-level
# roto → kustomize "missing Resource metadata" → la App kyverno-policies
# jamás sincronizaba → webhooks-scopeados moría sin pista. TODA
# inyección multi-línea va por inject_placeholder (common.sh): solo
# líneas no-comentario, ocurrencia única, indent del destino real,
# y valida el YAML resultante ANTES de escribir:
POL="$PLATFORM_DIR/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml"
if placeholder_pending "$POL" __COSIGN_PUB__; then
    run_cmd inject_placeholder "$POL" __COSIGN_PUB__ "$SECRETS_TMP/cosign.pub"
fi
gate "cosign-pub-inyectada" bash -c \
    "grep -q 'BEGIN PUBLIC KEY' '$POL' && ! grep -q '__COSIGN_PUB__' '$POL'"
# entry del generator EN EL MISMO COMMIT que el .enc.yaml (A7 +
# sincronía atómica — la decisión está anotada en el generator):
GEN="$PLATFORM_DIR/k8s/base/platform/jenkins-secrets/secret-generator.yaml"
# H4 corrida #13 (guard estructural — el grep por nombre matcheaba
# comentarios; instancia latente de la misma clase que rompió el
# regcred del IU en la 40):
yaml_lists_file "$GEN" secret-cosign-signing-key.enc.yaml || \
    run_cmd sed -i \
      '/secret-github-webhook-hmac.enc.yaml/a\  - secret-cosign-signing-key.enc.yaml' \
      "$GEN"
gate "cosign-key-en-generator" \
    yaml_lists_file "$GEN" secret-cosign-signing-key.enc.yaml

# ORDEN COMO MECANISMO de verdad (corrida #12): la App kyverno-policies
# es automated — el comentario "se sincroniza ÚLTIMA" no la frenaba: el
# policy con __COSIGN_PUB__ placeholder entró vivo desde la fase 35 y
# su webhook failurePolicy=Fail rechazó el canary de la 70 ("missing
# digest"; el fallo de EVALUACIÓN bloquea aunque el action sea Audit).
# El kustomization nace VACÍO (resources: []) y ESTA fase agrega el
# policy EN EL MISMO COMMIT que inyecta la pub real — mismo patrón
# runtime-entry que el generator de arriba (checks 18/18b/39):
KPK="$PLATFORM_DIR/k8s/base/kyverno-policies/kustomization.yaml"
# H4 corrida #13: el guard original era grep -q por nombre y el
# COMENTARIO del kustomization contiene ese nombre → habría matcheado
# el comentario y la entry jamás se agregaba (la MISMA clase que
# rompió el regcred del IU). Guard estructural:
if ! yaml_lists_file "$KPK" clusterpolicy-require-aegis-signature.yaml; then
    run_cmd python3 - "$KPK" <<'EOF'
import sys
p = sys.argv[1]
t = open(p).read().replace(
    "resources: []",
    "resources:\n  - clusterpolicy-require-aegis-signature.yaml")
open(p, "w").write(t)
EOF
fi
gate "policy-en-kustomization" \
    yaml_lists_file "$KPK" clusterpolicy-require-aegis-signature.yaml
# Patrón A-2c (reporte in-VM #14): el error de una inyección/entry
# mala se detectaba TRES eslabones después (en el sync de ArgoCD,
# donde el mensaje ya no apunta a la causa) — buildear el directorio
# afectado ACÁ, antes del commit. Este dir es kustomize PLANO (el de
# argocd-secrets no se puede buildear local por el generator KSOPS;
# su equivalente es el dry-run=server del CR en la 70):
gate "kustomize-build-policies" bash -c \
  "kubectl kustomize '$PLATFORM_DIR/k8s/base/kyverno-policies' >/dev/null"

# inyectar el CA de aegis en los values de kyverno (T1; no existía
# hasta que cert-manager lo emitió en fase 35 — mismo patrón que
# __COSIGN_PUB__). global.caCertificates.data espera el PEM con la
# indentación del bloque:
# CR-2 corrida #14: el inyector viejo tomaba el indent de la PRIMERA
# línea con el placeholder — que era el COMENTARIO del values (indent
# 2) — y el PEM quedaba fuera del block scalar (indent 6) → helm
# template "did not find expected key" → ComparisonError → la App
# kyverno jamás sincronizaba. inject_placeholder ignora comentarios
# y toma el indent de la línea REAL del bloque:
KYV="$PLATFORM_DIR/k8s/base/platform/kyverno/values.yaml"
CA_INYECTADO_ESTA_CORRIDA=false
if placeholder_pending "$KYV" __AEGIS_CA_PEM__; then
    kubectl -n cert-manager get secret aegis-internal-ca \
        -o jsonpath='{.data.ca\.crt}' | base64 -d \
        > "$SECRETS_TMP/aegis-ca.pem"
    run_cmd inject_placeholder "$KYV" __AEGIS_CA_PEM__ "$SECRETS_TMP/aegis-ca.pem"
    CA_INYECTADO_ESTA_CORRIDA=true
fi
gate "ca-inyectado-en-kyverno" bash -c \
    "grep -q 'BEGIN CERTIFICATE' '$KYV' && ! grep -q '__AEGIS_CA_PEM__' '$KYV'"

# clase F auditoría: sin || true que trague un commit fallido real:
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(supply-chain): cosign key cifrada + pub y CA inyectados"
git_push_verified "$PLATFORM_DIR"
argo_sync jenkins-secrets    # ahora el generator completa los 7
# F-B #15: Synced solo cuenta a la revisión RECIÉN pusheada:
argo_secrets_gate jenkins-secrets 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
gate "cosign-secret-vivo" poll 180 5 bash -c \
  "kubectl -n jenkins-system get secret cosign-signing-key >/dev/null 2>&1"

# ── 80.3 PRIMERA IMAGEN FIRMADA (gate bisagra de la fase) ──────────
REG_HOST="$REGISTRY_HOST_INTERNAL"   # fuente única (P3 auditoría)
registry_creds "$REG_HOST" "$REGISTRY_CLUSTER_IP"
# P1.8 reporte in-VM #14: cada RETOME de esta fase re-disparaba un
# build firmado (~10 min) aunque YA existiera una imagen firmada
# válida — iterar la fase costaba 3x lo necesario. Idempotencia
# real: si el ÚLTIMO tag del registry verifica contra cosign.pub, no
# hay nada que construir. El digest sale SIEMPRE del manifest del
# REGISTRY (Docker-Content-Digest) — P3 auditoría: el camino
# post-build que raspaba el console de Jenkins murió; una sola
# fuente para ambos caminos. P1.15: la LECTURA falla explícita
# (retry + die) — "curl falló" ≠ "sin tags":
registry_last_signed_candidate() {
    local tags_json
    tags_json="$(retry_net 3 curl -fsS --max-time 30 \
        --netrc-file "$SECRETS_TMP/registry.netrc" \
        --cacert "$SECRETS_TMP/aegis-ca.crt" \
        "https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/tags/list")" || \
        die "no pude LEER el catálogo del registry (red/registry caído) — esto NO es 'sin tags'"
    LAST_TAG="$(jq -r '.tags[]?' <<< "$tags_json" \
      | grep -E '^main-[0-9]{6}$' | sort | tail -n1 || true)"
    DIGEST=""
    if [[ -n "$LAST_TAG" ]]; then
        DIGEST="$(retry_net 3 curl -fsSI --max-time 30 \
            --netrc-file "$SECRETS_TMP/registry.netrc" \
            --cacert "$SECRETS_TMP/aegis-ca.crt" \
            -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
            "https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/manifests/$LAST_TAG" \
          | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:"{print $2}')" || \
            die "el tag $LAST_TAG existe pero no pude leer su manifest (red/registry) — no es un catálogo vacío"
    fi
}
LAST_TAG="" DIGEST=""
registry_last_signed_candidate
if [[ -n "$DIGEST" ]] && DOCKER_CONFIG="$SECRETS_TMP/docker" cosign verify \
     --key "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub" \
     --registry-cacert "$SECRETS_TMP/aegis-ca.crt" \
     --insecure-ignore-tlog=true \
     "$REGISTRY_CLUSTER_IP:5000/hello-aegis@$DIGEST" >/dev/null 2>&1; then
    log_ok "imagen firmada VÁLIDA ya en el registry ($LAST_TAG) — build omitido (idempotencia de retome, P1.8)"
else
    log_info "re-disparando build del canary para producir la primera imagen FIRMADA"
    NEXT_SIGN="$(jenkins_next_build hello-aegis-mb/job/main)"  # ANTES del push (carrera lastBuild #9)
    run_cmd retry_net 3 bash -c "cd \$(mktemp -d) && \
      git clone --depth 1 https://github.com/$GH_OWNER/$APP_REPO.git app && \
      cd app && git commit --allow-empty -m 'ci: first signed build' && \
      git push"
    gate "build-firmado-verde" jenkins_wait_build hello-aegis-mb/job/main 1800 "$NEXT_SIGN"
    # P3 auditoría 2026-07-18: el digest se relee del MANIFEST del
    # registry (la misma fuente que el camino idempotente) — el
    # raspado del console de Jenkins era un formato frágil de un
    # build que en un retome podía ser otro:
    registry_last_signed_candidate
fi
# verificación REAL de la firma (capability real, no "el stage dice"
# — y el gate corre SIEMPRE, también en el camino del skip): va por
# IP directa (el host no resuelve .svc — A30; el cert del registry
# tiene la IP en SANs). --insecure-ignore-tlog NO es TOFU: la firma
# se verifica completa contra cosign.pub — solo se omite el log de
# transparencia público, que nunca se usó (--tlog-upload=false en el
# pipeline, registry privado).
gate "digest-extraido" test -n "$DIGEST"
gate "firma-verificada-real" bash -c \
  "DOCKER_CONFIG='$SECRETS_TMP/docker' cosign verify \
     --key '$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub' \
     --registry-cacert '$SECRETS_TMP/aegis-ca.crt' \
     --insecure-ignore-tlog=true \
     '$REGISTRY_CLUSTER_IP:5000/hello-aegis@$DIGEST' >/dev/null"

# ── 80.4 Kyverno: install → Audit implícito → Enforce al final ─────
argo_sync kyverno-base
argo_sync kyverno 600
# P1.1 auditoría 2026-07-18 (CONFIRMADO EN VIVO): el CA va montado
# por subPath — kubelet NO refresca subPath mounts al cambiar el
# Secret/ConfigMap. Si los controllers ya corrían cuando ESTA corrida
# inyectó el CA, siguen con el viejo/inexistente en memoria → x509 al
# verificar contra el registry → deny fail-closed → gate de 920s
# vencido con diagnóstico lejano. Tras una inyección NUEVA, rollout
# restart de TODOS los deploys de kyverno + espera real (regla de
# oro anti-clase-D: config de pod vivo ⇒ restart o checksum):
if [[ "$CA_INYECTADO_ESTA_CORRIDA" == "true" ]]; then
    log_info "CA inyectado en ESTA corrida — rollout restart de los controllers de Kyverno (subPath no refresca solo)"
    run_cmd bash -c "kubectl -n kyverno get deploy -o name \
        | xargs -r -n1 kubectl -n kyverno rollout restart"
    while IFS= read -r d; do
        gate "kyverno-restart-${d##*/}" wait_rollout kyverno "$d" 600
    done < <(kubectl -n kyverno get deploy -o name)
fi

# A v1.1 aplicado a Kyverno (mismo patrón, otro proveedor): la
# ClusterPolicy la gobierna el admission webhook de Kyverno — que
# acaba de reiniciarse por el CA. "App Healthy" no prueba que
# atienda; los ENDPOINTS sí. Sin esto, el sync de abajo puede morir
# con el mismo "no endpoints available" que mató la 35 en la v1.1:
gate "kyverno-webhook-sirviendo" \
    webhook_serving kyverno kyverno-svc 300

# LA ÚLTIMA App del init (D5): la policy Enforce entra cuando ya
# existe imagen firmada + verificada:
argo_sync kyverno-policies
# P1.14: Synced solo cuenta a la revisión del commit de ESTA fase:
argo_secrets_gate kyverno-policies 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
# P1.9 auditoría: era single-shot sobre un paso ASÍNCRONO (el
# controller admite la policy y recién después setea Ready):
gate "policy-ready" poll 180 5 bash -c \
  "kubectl get clusterpolicy require-aegis-signature \
     -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null \
   | grep -q True"
# clase D auditoría: este gate corría ANTES del sync de la policy —
# el ValidatingWebhookConfiguration scopeado lo GENERA Kyverno al
# existir la policy; verificarlo antes era pedirle el efecto antes
# que la causa. Ahora: después de policy-ready, con poll:
gate "webhooks-scopeados" poll 180 5 bash -c \
  "kubectl get validatingwebhookconfigurations -o yaml 2>/dev/null \
   | grep -q 'org-canary'"
# (A44: el namespaceSelector del webhook ES el blast radius del
#  failurePolicy Fail — verificar el objeto generado, no la policy)

# ── 80.5 gate final del supply-chain (el de 3.E.3, codificado) ─────
# CR-2-poll corrida #14: tras policy-ready el Deployment todavía
# referencia el ÚLTIMO tag PRE-firma (el IU aún no bumpeó al build
# firmado de 80.3) — un restart inmediato produce pods DENEGADOS
# legítimamente (carrera que se destraba sola pero ensucia el gate).
# Esperar a que el ciclo IU→ArgoCD despliegue la imagen firmada (el
# autogen de Kyverno muta el Deployment a digest en el admission):
gate_diag "canary-pineado-a-digest" \
  'kubectl -n org-canary get deploy hello-aegis \
     -o jsonpath="{.spec.template.spec.containers[0].image}"; echo;
   kubectl -n argocd logs deploy/argocd-repo-server --since=15m 2>/dev/null | tail -n 20' \
  poll 900 15 bash -c \
  "kubectl -n org-canary get deploy hello-aegis \
     -o jsonpath='{.spec.template.spec.containers[0].image}' \
   | grep -q '@sha256:'"
# positivo: rollout del canary admitido y MUTADO a digest. Patrón B
# (reporte in-VM #14) también acá: al fallar debe DISTINGUIRSE
# "denegado por Kyverno" de "timeout de rollout" — los events del ns
# y el describe del deploy traen el motivo real:
run_cmd kubectl -n org-canary rollout restart deploy/hello-aegis
# Hallazgo B v1.0: el restart dispara un despliegue y la mutación de
# Kyverno (pinea el digest en el template) dispara un SEGUNDO — en
# la ventana conviven 3+ ReplicaSets con pods naciendo y muriendo.
# El gate viejo midió a los 5s con "items[0] del namespace" y
# encontró un pod VIEJO (la propia evidencia mostraba el pod nuevo
# Running y pineado — veredicto contradicho por su evidencia).
# Familia convergencia, instancia #5. Ahora: EXISTENCIA→ESTABILIDAD
# (k8s_converged absorbe la cascada re-esperando cada rollout) →
# medir SOLO los pods del RS VIGENTE (deploy_current_pods_ok):
gate_diag "positivo-rollout-convergido" \
  'kubectl -n org-canary get rs 2>/dev/null;
   kubectl -n org-canary get pods 2>/dev/null;
   kubectl -n org-canary get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 10' \
  k8s_converged org-canary deploy/hello-aegis 300
_positivo_ok() {
    deploy_current_pods_ok org-canary hello-aegis \
      '.status.phase == "Running" and (.spec.containers[0].image | test("@sha256:"))'
}
gate_diag "positivo-admitido-y-digest" \
  'kubectl -n org-canary get pods -o wide 2>/dev/null | tail -n 6;
   kubectl -n org-canary get deploy hello-aegis -o jsonpath="{.spec.template.spec.containers[0].image}" 2>/dev/null; echo;
   if kubectl -n org-canary get pods -o jsonpath="{range .items[*]}{.spec.containers[0].image}{\"\n\"}{end}" 2>/dev/null | grep -q "@sha256:"; then
     log_warn "POSIBLE TIMING, no fallo real: hay pods con la imagen pineada a digest — el estado esperado está PRESENTE pero la cascada de despliegues no convergió (B v1.0); un retome suele pasar en segundos";
   fi' \
  poll 120 5 _positivo_ok
# netpol (W-07 / P-D): el tenant está AISLADO — desde el canary (ya
# corriendo, firmado, alpine con wget) NO se alcanza el pipeline.
# jenkins está UP; el egress del tenant solo permite DNS, así que el
# connect a :8080 debe TIMEOUTear. Si conecta, la netpol no aísla:
_netpol_aislado() {
    # exec de prueba (canal exec vivo + pod Ready) vía el Deployment —
    # kubectl elige el pod, sin items[0] del namespace (check 72):
    kubectl -n org-canary exec deploy/hello-aegis -- true 2>/dev/null \
        || { echo "no se pudo exec en el canary (¿NotReady?) — no es veredicto de netpol"; return 1; }
    # connect real: jenkins UP, egress del tenant solo-DNS → debe fallar.
    # Si conecta, la netpol NO aísla:
    if kubectl -n org-canary exec deploy/hello-aegis -- \
         wget -q -T 4 -O /dev/null http://jenkins.jenkins-system:8080 2>/dev/null; then
        echo "FALLO: el canary alcanzó jenkins:8080 — la netpol NO aísla el egress del tenant"
        return 1
    fi
    return 0   # timeout con exec vivo = aislado (lo esperado)
}
gate_diag "netpol-tenant-aislado" \
  'kubectl -n org-canary get netpol 2>/dev/null;
   kubectl -n org-canary get pod -l app=hello-aegis 2>/dev/null' \
  _netpol_aislado
# probes del gate final (CR-3/CR-4 corrida #14): en org-canary un
# pod PELADO lo rechazan PSS restricted o la ResourceQuota AUNQUE
# Kyverno no interceptara nada (falso verde del negativo), y en
# jenkins-system la quota estricta lo rechaza ANTES de llegar a
# Kyverno (falso rojo del scope). Los probes son PSS/quota-compliant
# — lo ÚNICO no-compliant del negativo es la firma:
PROBE_RES='"resources":{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"cpu":"50m","memory":"32Mi"}}'
PROBE_SC='"securityContext":{"runAsNonRoot":true,"allowPrivilegeEscalation":false,"seccompProfile":{"type":"RuntimeDefault"},"capabilities":{"drop":["ALL"]}}'
NEG_IMG="$REGISTRY_CLUSTER_IP:5000/hello-aegis:doesnotexist"
NEG_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"unsigned-probe\",\"image\":\"$NEG_IMG\",\"command\":[\"true\"],$PROBE_SC,$PROBE_RES}]}}"
# negativo: imagen NO firmada RECHAZADA **POR LA POLICY** — el assert
# es sobre el MENSAJE del deny (verificado 3x en vivo #14: el deny
# real cita require-aegis-signature; PSS o quota citan otra cosa).
# P1.17 auditoría 2026-07-18: un deny por "context deadline"/"failed
# calling webhook" del webhook RECIÉN levantado (o recién restarteado
# por el fix del CA) es TRANSITORIO — morir ahí daba el diagnóstico
# equivocado en el último gate del init. Hasta 3 intentos; solo el
# deny de la POLICY (o la admisión indebida) son veredictos finales:
NEG_OUT="" NEG_OK=false
for _i in 1 2 3; do
    probe_reset org-canary unsigned-probe
    if NEG_OUT="$(kubectl -n org-canary run unsigned-probe --restart=Never \
          --image="$NEG_IMG" --overrides="$NEG_OVR" 2>&1)"; then
        # limpieza best-effort camino al die (output a stderr, no tragado):
        kubectl -n org-canary delete pod unsigned-probe \
            --ignore-not-found >&2 || true
        _gate_record "negativo-rechazado" fail 0
        die "GATE negativo-rechazado FALLÓ — el pod con imagen SIN FIRMA fue ADMITIDO en org-canary"
    fi
    if grep -q 'require-aegis-signature' <<< "$NEG_OUT"; then
        NEG_OK=true
        break
    fi
    if grep -qiE 'context deadline|failed calling webhook|connection refused|no endpoints available' <<< "$NEG_OUT"; then
        log_warn "negativo-rechazado: el webhook aún no responde (transitorio post-restart, intento $_i/3) — espero 20s"
        sleep 20
        continue
    fi
    break   # rechazo ajeno a la policy y sin firma de transitorio: veredicto
done
if [[ "$NEG_OK" == "true" ]]; then
    _gate_record "negativo-rechazado" pass 0
    log_ok "GATE negativo-rechazado (el deny cita require-aegis-signature — no PSS, no quota)"
else
    printf '%s\n' "$NEG_OUT" >&2
    _gate_record "negativo-rechazado" fail 0
    die "GATE negativo-rechazado FALLÓ — el rechazo NO lo firmó la policy (¿PSS/quota tapando a Kyverno? CR-4 #14; arriba: el mensaje real)"
fi
# negativo DENY-BY-DEFAULT (W-04): imagen de OTRO nombre y OTRO
# registry, sin firma. Con la allowlist vieja (hello-aegis*) ENTRABA
# sin verificar; con imageReferences:* debe ser RECHAZADA citando la
# policy — es EL gate que prueba que ya no hay allowlist por nombre.
# Mismo patrón anti-transitorio (P1.17) que el negativo de arriba:
DBD_IMG="docker.io/library/nginx:1.27"
DBD_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"dbd-probe\",\"image\":\"$DBD_IMG\",\"command\":[\"true\"],$PROBE_SC,$PROBE_RES}]}}"
DBD_OUT="" DBD_OK=false
for _i in 1 2 3; do
    probe_reset org-canary dbd-probe
    if DBD_OUT="$(kubectl -n org-canary run dbd-probe --restart=Never \
          --image="$DBD_IMG" --overrides="$DBD_OVR" 2>&1)"; then
        kubectl -n org-canary delete pod dbd-probe --ignore-not-found >&2 || true
        _gate_record "negativo-deny-by-default" fail 0
        die "GATE negativo-deny-by-default FALLÓ — nginx (OTRO nombre/registry, SIN FIRMA) fue ADMITIDO: la policy sigue siendo allowlist, no deny-by-default"
    fi
    if grep -q 'require-aegis-signature' <<< "$DBD_OUT"; then DBD_OK=true; break; fi
    if grep -qiE 'context deadline|failed calling webhook|connection refused|no endpoints available' <<< "$DBD_OUT"; then
        log_warn "negativo-deny-by-default: webhook transitorio (intento $_i/3) — 20s"; sleep 20; continue
    fi
    break
done
if [[ "$DBD_OK" == "true" ]]; then
    _gate_record "negativo-deny-by-default" pass 0
    log_ok "GATE negativo-deny-by-default (nginx sin firma RECHAZADO citando la policy — no hay allowlist por nombre)"
else
    printf '%s\n' "$DBD_OUT" >&2
    _gate_record "negativo-deny-by-default" fail 0
    die "GATE negativo-deny-by-default FALLÓ — el rechazo de nginx NO lo firmó la policy (arriba: el mensaje real)"
fi
# scope: fuera de org-canary NO aplica — una imagen pública sin
# firma DEBE ser admitida en jenkins-system (si Kyverno la rechaza,
# el namespaceSelector del webhook está mal y este gate FALLA).
# Solo resources (la quota exige limits); SIN securityContext
# restricted: busybox corre root y runAsNonRoot lo mataría en
# runtime — jenkins-system no es restricted y el gate es de ADMISIÓN:
# busybox PINNEADO (P3 auditoría: era el único probe sin pin) +
# probe_reset (P1.8):
SCOPE_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"scope-probe\",\"image\":\"busybox:1.36\",\"command\":[\"true\"],$PROBE_RES}]}}"
probe_reset jenkins-system scope-probe
gate_diag "scope-fuera-admite" \
  'kubectl -n jenkins-system get events --sort-by=.lastTimestamp | tail -n 10' \
  bash -c "kubectl -n jenkins-system run scope-probe --rm -i --restart=Never \
     --image=busybox:1.36 --overrides='$SCOPE_OVR' >/dev/null"
# W-08 / EV-03: los gates fail-closed force-kill VERIFICAN la propiedad
# más fuerte del producto (Kyverno caído → org-canary RECHAZA). Son
# DISRUPTIVOS (crashean el admission controller), así que NO corren en
# cada bootstrap; SÍ en la validación con AEGIS_VALIDATE_FAILCLOSED=1.
# Cuando NO corren se REGISTRAN como skipped — NUNCA silencioso (EV-08):
# ningún reporte puede afirmar fail-closed si el gate no midió (EV-03).
_failclosed_gates() {
    # crash DURO (SIGKILL --force, NO graceful: el shutdown graceful
    # quita los webhooks de Kyverno y no probaría nada). failurePolicy
    # Fail + webhook muerto: org-canary (en el namespaceSelector)
    # RECHAZA; argocd (fuera) ADMITE — blast radius acotado (3.E.3 t4/5).
    log_warn "fail-closed: matando DURO el admission controller de Kyverno (disruptivo, se recupera solo)"
    kubectl -n kyverno delete pod -l app.kubernetes.io/component=admission-controller \
        --grace-period=0 --force >&2 || true
    local i
    for i in $(seq 1 30); do   # esperar a que el endpoint DESAPAREZCA
        kubectl -n kyverno get endpoints kyverno-svc \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q . || break
        sleep 2
    done
    # guard: si el webhook sigue vivo, el kill no tomó — NO es veredicto
    # de fail-closed (sería falso fail-open por selector de delete malo):
    if kubectl -n kyverno get endpoints kyverno-svc \
         -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q .; then
        _gate_record "failclosed-org-canary-rechaza" fail 0
        die "GATE fail-closed: NO se pudo tumbar el webhook de Kyverno (endpoint vivo tras el kill) — revisar el selector del delete, no es veredicto"
    fi
    local fc_ovr out
    fc_ovr="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"fc-probe\",\"image\":\"$DBD_IMG\",\"command\":[\"true\"],$PROBE_SC,$PROBE_RES}]}}"
    # (1) org-canary RECHAZA por el webhook caído (fail-closed real).
    #     El probe es PSS-compliant → pasa PSS y LLEGA al webhook muerto:
    if out="$(kubectl -n org-canary run fc-probe --restart=Never \
              --image="$DBD_IMG" --overrides="$fc_ovr" 2>&1)"; then
        kubectl -n org-canary delete pod fc-probe --ignore-not-found >&2 || true
        _gate_record "failclosed-org-canary-rechaza" fail 0
        die "GATE fail-closed FALLÓ — con Kyverno CAÍDO org-canary ADMITIÓ un pod: es fail-OPEN, no fail-closed"
    fi
    grep -qiE 'failed calling webhook|context deadline|no endpoints|connection refused' <<< "$out" \
        || { printf '%s\n' "$out" >&2; _gate_record "failclosed-org-canary-rechaza" fail 0
             die "GATE fail-closed FALLÓ — org-canary rechazó pero NO por el webhook caído (¿PSS/quota? mensaje arriba)"; }
    _gate_record "failclosed-org-canary-rechaza" pass 0
    log_ok "GATE failclosed-org-canary-rechaza (Kyverno caído → org-canary RECHAZA por el webhook — fail-closed REAL)"
    # (2) argocd ADMITE (fuera del selector → la plataforma no congela):
    if out="$(kubectl -n argocd run fc-probe --restart=Never \
              --image=busybox:1.36 --command -- true 2>&1)"; then
        kubectl -n argocd delete pod fc-probe --ignore-not-found >&2 || true
        _gate_record "failclosed-argocd-admite" pass 0
        log_ok "GATE failclosed-argocd-admite (Kyverno caído → argocd ADMITE — blast radius acotado)"
    else
        printf '%s\n' "$out" >&2
        _gate_record "failclosed-argocd-admite" fail 0
        die "GATE fail-closed FALLÓ — con Kyverno caído argocd NO admitió: el namespaceSelector no acota (toda la plataforma congelaría)"
    fi
    # recuperación: el Deployment recrea el admission controller:
    log_info "fail-closed: esperando recuperación de Kyverno (rollout del admission controller)"
    wait_rollout kyverno deployment.apps/kyverno-admission-controller 300 \
        || log_warn "Kyverno admission controller no volvió en 300s — REVISAR antes de seguir usando el cluster"
}
if [[ "${AEGIS_VALIDATE_FAILCLOSED:-}" == "1" || "${AEGIS_VALIDATE_FAILCLOSED:-}" == "true" ]]; then
    _failclosed_gates
else
    _gate_record "failclosed-org-canary-rechaza" skipped 0
    _gate_record "failclosed-argocd-admite" skipped 0
    log_warn "gates fail-closed force-kill: SKIPPED (REGISTRADO, no silencioso) — correr con AEGIS_VALIDATE_FAILCLOSED=1 en la validación; sin eso la propiedad fail-closed NO está medida (EV-03)"
fi

log_ok "SUPPLY-CHAIN COMPLETO: scan bloqueante + firma + Enforce \
fail-closed acotado. El init terminó: plataforma v2 de punta a punta."
