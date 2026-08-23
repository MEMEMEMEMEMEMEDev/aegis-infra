#!/usr/bin/env bash
# FASE 40 — registry + PKI interno, "4 pasos en orden estricto"
# (2026-07-02:46), CON TLS DESDE EL DÍA UNO (desvío deliberado del
# orden histórico que la fuente misma pide: 2026-07-04:7).
# Incluye el ÚNICO bloque sudo del init (CA al host, por nodo).
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

# ── 40.0 credenciales del registry (ORIGEN ÚNICO — A27) ────────────
# password random + htpasswd + LOS 4 regcred derivados EN EL MISMO
# PROCESO (derive_htpasswd_and_regcreds hace imposible el mismatch):
secrets_workdir
REG_HOST="$REGISTRY_HOST_INTERNAL"   # fuente única (P3 auditoría)
# gen_or_restore: re-run reutiliza el MISMO password (bug 6 — si
# regenerara, el htpasswd nuevo no matchearía los regcred viejos).
# Sin pausa humana de resguardo: el password vive cifrado en el
# store (recuperable con la age key — D11: el único irreducible
# que se resguarda a mano es la age key):
PASS="$(gen_or_restore registry_pass gen_password_b64)"
derive_htpasswd_and_regcreds aegis-dev "$PASS" "$REG_HOST"

B="$PLATFORM_DIR/k8s/base"
make_enc_secret registry-htpasswd registry-system \
    "$B/registry-system/registry-htpasswd.enc.yaml" \
    "htpasswd=$SECRETS_TMP/htpasswd"
for pair in \
    "regcred-internal:jenkins-system:$B/platform/jenkins-secrets/secret-regcred-internal.enc.yaml" \
    "regcred-kyverno:kyverno:$B/kyverno/secret-regcred-kyverno.enc.yaml" \
    "regcred-internal:org-canary:$PLATFORM_DIR/k8s/organizations/org-canary/secret-regcred-internal.enc.yaml"
do
    IFS=: read -r name ns dest <<< "$pair"
    # --type OBLIGATORIO (corrida #9, EL bloqueante de la fase 60):
    # sin él, make_enc_secret genera type OPAQUE y el kubelet lo
    # IGNORA como imagePullSecret ("no basic auth credentials" →
    # ImagePullBackOff del sidecar cosign) aunque el mismo secret
    # funcione montado como volumen. dockerconfigjson sirve para
    # AMBOS usos. (El comentario previo afirmaba que "el generator
    # fija el type" — era FALSO, nadie lo fijaba: A38, no afirmar
    # estado no verificado.) A34: type INMUTABLE — sobre un cluster
    # vivo con el Opaque viejo: kubectl delete secret + re-sync.
    make_enc_secret "$name" "$ns" "$dest" \
        --type kubernetes.io/dockerconfigjson \
        ".dockerconfigjson=$SECRETS_TMP/dockerconfig.json"
done
# entry del generator de argocd-secrets EN EL MISMO COMMIT que su
# .enc.yaml (patrón cosign / regla temporal — corrida #4: el entry
# estático de un archivo de ESTA fase rompía el build de la App en
# la fase 35, y con él TODOS los secrets de la App):
GEN_ARGO="$B/platform/argocd-secrets/secret-generator.yaml"
# H4 corrida #13: el grep -q por nombre matcheaba el COMENTARIO del
# generator ("→ la agrega la fase 40") → el sed nunca corría → el
# secret jamás nacía ("could not fetch secret" del IU, 1 fase
# después). Guard ESTRUCTURAL (entry de lista) + verificación del
# RESULTADO — nunca más un paso tragado por || true:
# ACÁ SE AGREGABA a la lista del generador de argocd-secrets el regcred
# del Image Updater. Se fue con el componente en #59: era la credencial
# con la que el updater leía el registry para descubrir tags nuevos, y
# sin updater no hay quién la use.
#
# El nombre del archivo NO se escribe acá aunque sea sólo un comentario:
# el check 4 de verify-static toma como PRODUCTOR toda mención literal
# de un *.enc.yaml en las fases, comentarios incluidos. Sobre-detecta a
# propósito —fallar de más es más seguro que perderse un productor—, así
# que nombrarlo haría que el verificador buscara para siempre una entry
# que ya no existe.
# clase F auditoría: sin || true (staged vacío = no-op; fallo real
# con staged = muere ACÁ, no como "kustomize roto" 2 gates después):
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(registry): htpasswd + 4 regcred derivados atomicos"
git_push_verified "$PLATFORM_DIR"

# ── 40.1 PKI + registry por GitOps (orden estricto) ────────────────
argo_sync aegis-ca-issuer          # ya sync en fase 35; idempotente
argo_sync registry 600
gate "registry-tls-secret" bash -c \
  "kubectl -n registry-system get secret registry-tls >/dev/null"
gate "registry-htpasswd-vivo" bash -c \
  "kubectl -n registry-system get secret registry-htpasswd >/dev/null"
# P3 auditoría 2026-07-18: REGISTRY_CLUSTER_IP del conf se hornea en
# cert/mirror/netrc/policy/probes y JAMÁS se validaba contra el
# Service REAL — un typo en el conf explotaba como x509/timeout a
# fases de distancia. La fuente de verdad es el cluster:
gate_diag "clusterip-coincide-con-el-service" \
  'kubectl -n registry-system get svc registry -o jsonpath="{.spec.clusterIP}"; echo " (conf: $REGISTRY_CLUSTER_IP)"' \
  bash -c "kubectl -n registry-system get svc registry \
     -o jsonpath='{.spec.clusterIP}' | grep -qx '$REGISTRY_CLUSTER_IP'"

# ── 40.2 CA al HOST (bloque sudo; POR NODO en hetzner) ─────────────
# El kubelet no resuelve .svc.cluster.local: mirror por ClusterIP
# fija + ca_file (2026-07-02:16-28). En v2 esto es un ROLE ANSIBLE
# (salda el "pendiente" de 2026-07-02:132), no un bloque a mano:
log_info "role registry-host-trust (sudo): aegis-ca.pem + registries.yaml + restart k3s"
run_cmd kubectl -n cert-manager get secret aegis-internal-ca \
    -o jsonpath='{.data.ca\.crt}' > /dev/null   # existencia, sin dump
ansible_become_setup   # NOPASSWD => sin prompt; si no, UNA vez a tmpfs
# retry_net: mismo contrato que los playbooks de la fase 20 (E-1 —
# ansible idempotente por diseño, re-correr es seguro y retoma):
run_cmd retry_net 2 "$PLATFORM_DIR"/ansible/.venv/bin/ansible-playbook \
    -i "$PLATFORM_DIR"/ansible/inventory/hosts.ini \
    "$PLATFORM_DIR"/ansible/playbooks/registry-host-trust.yml \
    "${ANSIBLE_BECOME_ARGS[@]}" \
    -e registry_cluster_ip="$REGISTRY_CLUSTER_IP"

# gate del host-trust (corrida #7, bug B): la 40.2 NO tenía gate
# propio — su fallo (tarea censurada del ca.crt) se difería al pull
# de la fase 50 con un x509 críptico. El role deja aegis-ca.pem +
# registries.yaml en el host (perfil local = este host; hetzner los
# valida por-nodo el propio playbook con failed_when):
gate "host-confia-en-el-CA" bash -c \
  "[[ -s /etc/rancher/k3s/aegis-ca.pem && -s /etc/rancher/k3s/registries.yaml ]]"

# ── 40.2b DNS del cluster SANO tras el restart de k3s (bug B) ──────
# El "restart k3s" del role reinicia CoreDNS y el API server; si el
# DNS in-cluster queda roto (capa externa: forward al stub de
# systemd-resolved — resuelto por resolv-conf en fase 20; capa
# interna: el plugin kubernetes pierde el watch tras el restart), el
# primer build de la fase 50 falla al pullear del registry con un
# "lookup ...: Try again" a 2 fases de distancia. Se CORTA acá, con
# diagnóstico, verificando la resolución REAL de kubernetes.default Y
# del registry (un pod efímero que ejerce el camino DNS completo):
DNS_PROBE="nslookup kubernetes.default.svc.cluster.local && \
nslookup registry.registry-system.svc.cluster.local"
# P1.8 auditoría: probe_reset ANTES de cada intento — si el attach
# del kubectl run vence, el pod queda y los reintentos morían TODOS
# con AlreadyExists (el retry se auto-anulaba):
if ! retry_net 6 bash -c \
     "kubectl -n default delete pod dns-probe --ignore-not-found --now >/dev/null 2>&1; \
      kubectl -n default run dns-probe --rm -i --restart=Never \
        --image=busybox:1.36 --command -- sh -c '$DNS_PROBE' >/dev/null 2>&1"; then
    log_warn "DNS in-cluster no resuelve tras el restart de k3s (bug B corrida #7)"
    log_warn "  capa externa: ¿k3s arrancó con resolv-conf? -> grep resolv-conf /etc/rancher/k3s/config.yaml"
    log_warn "  capa interna: el plugin kubernetes de CoreDNS pudo perder el watch — intento un rollout restart de CoreDNS"
    run_cmd kubectl -n kube-system rollout restart deploy/coredns
    # wait_rollout (E-1): tras el restart de k3s el nodo puede estar
    # re-pulleando; 120s convertía lento en fallo con la red móvil:
    wait_rollout kube-system deploy/coredns 600
fi
gate "dns-cluster-sano" retry_net 6 bash -c \
  "kubectl -n default delete pod dns-probe --ignore-not-found --now >/dev/null 2>&1; \
   kubectl -n default run dns-probe --rm -i --restart=Never \
     --image=busybox:1.36 --command -- sh -c '$DNS_PROBE' >/dev/null 2>&1"

# ── 40.3 gate REAL de pull (capability real, no proxy) ─────────────
# un pod de prueba que pullea una imagen del registry validaría el
# camino completo; todavía no hay imagen => el gate acá es TLS+auth.
# P2.4 auditoría 2026-07-18: el probe viejo usaba -k — NO validaba la
# cadena; un cert equivocado pasaba verde y explotaba en el pull del
# kubelet 2 fases después con un x509 críptico. Ahora el probe monta
# el ca.crt del Secret registry-tls (cert-manager con CA issuer lo
# incluye) y curl VALIDA la cadena de verdad. probe_reset por intento
# (P1.8) + retry_net (E-1: el primer run pullea alpine/curl y el
# attach puede vencer antes de que el pull termine):
TLS_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"restartPolicy\":\"Never\",\
\"containers\":[{\"name\":\"tls-probe\",\"image\":\"alpine/curl\",\
\"args\":[\"-fsS\",\"--max-time\",\"20\",\"--cacert\",\"/ca/ca.crt\",\
\"-o\",\"/dev/null\",\"-w\",\"%{http_code}\",\"https://$REG_HOST/v2/\"],\
\"volumeMounts\":[{\"name\":\"ca\",\"mountPath\":\"/ca\",\"readOnly\":true}]}],\
\"volumes\":[{\"name\":\"ca\",\"secret\":{\"secretName\":\"registry-tls\",\
\"items\":[{\"key\":\"ca.crt\",\"path\":\"ca.crt\"}]}}]}}"
gate "registry-tls-real" retry_net 6 bash -c \
  "kubectl -n registry-system delete pod tls-probe --ignore-not-found --now >/dev/null 2>&1; \
   kubectl -n registry-system run tls-probe --rm -i --restart=Never \
     --image=alpine/curl --overrides='$TLS_OVR' 2>/dev/null | grep -q 401"
# 401 = cadena TLS VALIDADA contra el CA + auth exigida (un curl -f
# contra cert inválido sale != 0 y no imprime código). El pull real
# lo prueba la fase 50 (primer build) — ese es el test definitorio.

log_ok "Registry con TLS propio + auth, host confiando en el CA \
(role Ansible, por nodo), regcreds derivados atómicos"
