#!/usr/bin/env bash
# FASE 20 — host kernel + K3s (+ Cilium en perfil hetzner).
# Reusa el bootstrap del repo de plataforma (ansible), que hereda
# los 10 patrones endurecidos de Hito 2 (A13) y el pin literal (A12).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

cd "$PLATFORM_DIR"

# venv de ansible del repo (regenerable de requirements.txt).
# El guard es el BINARIO, no el directorio (validación #3: el venv
# quedó creado con el pip install fallido y un guard por -d habría
# salteado la instalación en el re-run — half-done state):
if [[ ! -x ansible/.venv/bin/ansible-playbook ]]; then
    run_cmd python3 -m venv ansible/.venv
    # retry_net: pip descarga ~decenas de MB de wheels — con la red
    # móvil del operador (E-1) un corte transitorio mataba la fase y
    # el re-run "funcionaba" (mitad del cache ya bajado). El guard
    # por binario de arriba hace el retry seguro:
    run_cmd retry_net 3 ansible/.venv/bin/pip install -q \
        -r ansible/requirements.txt
fi
gate "ansible-instalado" test -x ansible/.venv/bin/ansible-playbook

# ── become UNA sola vez para los DOS playbooks (corrida #4: dos
#    --ask-become-pass = doble prompt + timeout de become) ──────────
secrets_workdir
ansible_become_setup

# ── host kernel + paquetes (sudo vía ansible become) ───────────────
# retry_net en los playbooks: bootstrap-host baja paquetes apt e
# install-k3s baja el binario (~70MB) de get.k3s.io — por la red
# móvil un corte transitorio mataba la fase con el playbook a medio
# camino y el re-run "funcionaba" (E-1). Ansible es idempotente POR
# CONTRATO (A13): re-correr el playbook entero es seguro y retoma
# donde el estado quedó:
log_info "bootstrap-host.yml (sysctl, módulos kernel, apt, /etc/rancher)"
run_cmd retry_net 2 ansible/.venv/bin/ansible-playbook \
    -i ansible/inventory/hosts.ini \
    ansible/playbooks/bootstrap-host.yml "${ANSIBLE_BECOME_ARGS[@]}"

# ── K3s pinneado ───────────────────────────────────────────────────
log_info "install-k3s.yml (pin en group_vars, --disable traefik/servicelb)"
run_cmd retry_net 2 ansible/.venv/bin/ansible-playbook \
    -i ansible/inventory/hosts.ini \
    ansible/playbooks/install-k3s.yml "${ANSIBLE_BECOME_ARGS[@]}"

# ── kubeconfig: copiar Y verificar target (A11) ────────────────────
run_cmd mkdir -p "$HOME/.kube"
# con --write-kubeconfig-mode 600 (group_vars) el origen es root:root
# 600, así que un `cp` de usuario ya NO puede leerlo: la copia va con
# privilegio y en UN paso deja dueño y modo correctos. Los dos lados
# están acoplados a propósito — cambiar uno sin el otro rompe la fase
# (check 85).
run_cmd sudo install -m 600 -o "$(id -u)" -g "$(id -g)" \
    /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
gate "kube-context" check_kube_context "$KUBE_CONTEXT_EXPECTED"

# ── perfil hetzner: Cilium ANTES de toda NetworkPolicy (1.2b,
#    ADR-0014: el netpol controller default de k3s no enforce) ─────
if [[ "$PROFILE" == "hetzner" ]]; then
    # pin desde group_vars; el valor de fábrica es un centinela que
    # OBLIGA a verificarlo contra el chart oficial antes del primer
    # run hetzner (regla: el binario/chart real, no memoria):
    CILIUM_VER="$(python3 -c "import yaml; \
print(yaml.safe_load(open('ansible/inventory/group_vars/all.yml'))['cilium_chart_version'])")"
    [[ "$CILIUM_VER" == VERIFICAR* ]] && die \
        "pin de cilium sin verificar en group_vars — fijarlo contra helm.cilium.io antes del perfil hetzner"
    run_cmd helm repo add cilium https://helm.cilium.io --force-update
    run_cmd helm upgrade --install cilium cilium/cilium \
        --version "$CILIUM_VER" -n kube-system \
        --set operator.replicas=1
    gate "cilium-ready" bash -c \
      "kubectl -n kube-system rollout status ds/cilium --timeout=300s >/dev/null"

    # enforcement POSITIVO (A-netpol, 2026-06-20: kube-router aceptó
    # el manifest y no pobló el ipset — el manifest NO es evidencia).
    # Baseline primero: sin policy el curl DEBE pasar (si no, el
    # "bloqueado" de después no probaría enforcement sino rotura):
    # P3 auditoría: el probe no era idempotente — un re-run con el ns
    # sobreviviente moría en el create. Limpieza previa (espera el
    # Terminating: un create contra un ns muriendo también falla):
    run_cmd kubectl delete ns netpol-probe --ignore-not-found --wait=true
    run_cmd kubectl create ns netpol-probe
    run_cmd kubectl -n netpol-probe run target --image=nginx:alpine --port=80
    run_cmd kubectl -n netpol-probe expose pod target --port=80
    run_cmd kubectl -n netpol-probe wait --for=condition=Ready pod/target --timeout=120s
    probe_reset netpol-probe probe-open   # P1.8: --rm + retry se auto-anula
    gate "netpol-baseline-abierto" bash -c \
      "kubectl -n netpol-probe run probe-open --rm -i --restart=Never \
         --image=alpine/curl -- curl -fsS -m 5 http://target >/dev/null"
    run_cmd kubectl -n netpol-probe apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all }
spec:
  podSelector: {}
  policyTypes: [Ingress]
YAML
    probe_reset netpol-probe probe-denied
    gate "netpol-enforcement-positivo" bash -c \
      "! kubectl -n netpol-probe run probe-denied --rm -i --restart=Never \
          --image=alpine/curl -- curl -fsS -m 5 http://target >/dev/null 2>&1"
    run_cmd kubectl delete ns netpol-probe --wait=false
fi

# ── user namespaces sin privilegios (corrida #8, bug D) ────────────
# El pod de buildah (probado verde en v1/WSL2) necesita userns
# rootless; Ubuntu >= 23.10 lo bloquea por default (apparmor). El
# sysctl lo relajó bootstrap-host — este gate lo EJERCE (unshare real
# como usuario sin privilegios) para que el veredicto llegue ACÁ, no
# en el primer build de la fase 50 con un "permission denied" críptico:
gate "userns-sin-privilegios" unshare --user --map-root-user true

# ── storageclass default (1.2c) ────────────────────────────────────
# barrido sesión 23 (familia convergencia, gemelo de coredns/H4 que
# NO había mordido aún): local-path lo crea el MISMO controlador de
# manifests async que coredns — el single-shot podía correr antes de
# que el SC exista. Existencia→medición:
gate "default-storageclass" wait_for 180 5 \
    "StorageClass default (local-path async, mismo controlador que coredns)" \
    check_default_storageclass

# ── smoke ──────────────────────────────────────────────────────────
gate "nodos-ready" bash -c \
  "kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null"
# EL gate que tumbaba la 20 con red móvil (E-1): el primer boot de
# k3s pullea coredns/local-path/metrics de docker.io y 120s de
# timeout convertía LENTO en FALLO (el re-run "funcionaba" porque el
# pull quedó cacheado). wait_rollout: espera generosa con evidencia
# periódica (qué pod está Pulling/BackOff) — lento ≠ mudo ≠ fallo:
gate "coredns-vivo" wait_rollout kube-system deploy/coredns 900

log_ok "K3s vivo, kubeconfig verificado, storage default presente"
