#!/usr/bin/env bash
# PHASE 20 — host kernel + K3s (+ Cilium on the hetzner profile).
# Reuses the platform repo's bootstrap (ansible), which inherits the
# 10 hardened patterns of Milestone 2 (A13) and the literal pin (A12).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

cd "$PLATFORM_DIR"

# the repo's ansible venv (regenerable from requirements.txt).
# The guard is the BINARY, not the directory (validation #3: the venv
# was left created by the failed pip install, and a guard on -d would
# have skipped the installation on the re-run — half-done state):
if [[ ! -x ansible/.venv/bin/ansible-playbook ]]; then
    run_cmd python3 -m venv ansible/.venv
    # retry_net: pip downloads ~tens of MB of wheels — on the
    # operator's mobile network (E-1) a transient cut killed the phase
    # and the re-run "worked" (half the cache already downloaded). The
    # binary guard above makes the retry safe:
    run_cmd retry_net 3 ansible/.venv/bin/pip install -q \
        -r ansible/requirements.txt
fi
gate "ansible-instalado" test -x ansible/.venv/bin/ansible-playbook

# ── become ONCE for BOTH playbooks (run #4: two
#    --ask-become-pass = a double prompt + a become timeout) ────────
secrets_workdir
ansible_become_setup

# ── host kernel + packages (sudo via ansible become) ───────────────
# retry_net on the playbooks: bootstrap-host downloads apt packages
# and install-k3s downloads the binary (~70MB) from get.k3s.io — over
# the mobile network a transient cut killed the phase with the
# playbook halfway through and the re-run "worked" (E-1). Ansible is
# idempotent BY CONTRACT (A13): re-running the whole playbook is safe
# and it resumes where the state was left:
log_info "bootstrap-host.yml (sysctl, kernel modules, apt, /etc/rancher)"
# AI is read HERE and not assumed: with AI=gpu this playbook also puts
# the NVIDIA container runtime on the host, and it does it BEFORE k3s
# exists so that k3s writes its containerd config with the handler
# already present. Both edges of the branch are declared, which is what
# check 115 demands of every phase that forks.
AI="${AI:-no}"

# WHAT THE NODE KEEPS BACK FOR THE MACHINE IT LIVES ON, derived here
# and handed in. The playbook stays dumb on purpose: it writes what it
# is given, and the arithmetic — the human's floor, the host's own
# daemons, the eviction margin — lives in one place, `aegis host`.
#
# AN EMPTY ANSWER IS LEGITIMATE, which is why this does not `die`. On a
# machine that could not be measured there is nothing to reserve from,
# and the playbook's `when` then writes no file at all. A missing
# reservation is VISIBLE — `allocatable == capacity`, which the alert
# NodoSinReservaParaElAnfitrion reports — while an invented one is not
# visible at all.
AEGIS_RESERVED_FILE=/etc/rancher/k3s/config.yaml.d/10-aegis-node-reserved.yaml
# What is there BEFORE the playbook, so that afterwards we can tell
# whether the reservation actually moved. It matters on an instance
# that already exists: `install-k3s.yml` is a no-op when the version
# matches, k3s does not restart, and a drop-in nobody re-read is a file
# that changes nothing while looking applied.
AEGIS_RESERVED_WAS="$(sudo -n cat "$AEGIS_RESERVED_FILE" 2>/dev/null || true)"

AEGIS_NODE_RESERVED="$("$AEGIS_ROOT/libexec/aegis-host" reservation --for kubelet 2>/dev/null || true)"
if [[ -n "$AEGIS_NODE_RESERVED" ]]; then
    log_info "the node will keep back $(printf '%s' "$AEGIS_NODE_RESERVED" | sed -n 's/^ *- "system-reserved=memory=\(.*\)"$/\1/p') for the host"
else
    log_warn "the node's reservation could not be derived: it will go on handing out the whole machine (aegis host show says what is missing)"
fi

# AS JSON, and this is a measured lesson rather than a style choice.
# `-e key=value` is SPLIT by ansible before it is parsed, so a value
# with newlines and quotes in it -- which a drop-in with its arithmetic
# written above it certainly has -- makes it fail while trying to read
# the INVENTORY, with an error that names hosts.ini and not the
# variable. Measured 2026-09-10 on the first run. A `-e` that starts
# with `{` is read as JSON instead: one line, quoting handled, newlines
# escaped.
AEGIS_RESERVED_JSON="$(printf '%s' "$AEGIS_NODE_RESERVED" | python3 -c \
    'import json,sys; print(json.dumps({"aegis_node_reserved": sys.stdin.read()}))')"
run_cmd retry_net 2 ansible/.venv/bin/ansible-playbook \
    -i ansible/inventory/hosts.ini \
    -e "aegis_ai=$AI" \
    -e "$AEGIS_RESERVED_JSON" \
    ansible/playbooks/bootstrap-host.yml "${ANSIBLE_BECOME_ARGS[@]}"

# ── pinned K3s ─────────────────────────────────────────────────────
log_info "install-k3s.yml (pin in group_vars, --disable traefik/servicelb)"
run_cmd retry_net 2 ansible/.venv/bin/ansible-playbook \
    -i ansible/inventory/hosts.ini \
    ansible/playbooks/install-k3s.yml "${ANSIBLE_BECOME_ARGS[@]}"

# Does the API answer? A function and not an inline command, because
# `wait_for` takes a LABEL before the command and an inline pipeline
# there is exactly how the label ate the verb the first time.
# THE KUBECONFIG THIS FUNCTION NEEDS DOES NOT EXIST YET. ~/.kube/config
# is written further down in THIS phase; up here `kubectl` alone talks to
# localhost:8080 and answers «connection refused» however healthy the
# cluster is. The first cloud instance (2026-09-22) died on exactly that:
# the API had been up for three minutes while this probe kept saying no,
# so the valve withdrew a reservation that was never the problem. Same
# lesson as the label bug below, one layer down — a valve whose probe can
# only say NO is a switch that turns the feature off on a timer. k3s's own
# kubeconfig is there from the first start; the user's copy is not.
_k3s_api_answers() {
    sudo -n env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get --raw=/readyz >/dev/null 2>&1 \
        || kubectl get --raw=/readyz >/dev/null 2>&1
}

# ── the reservation, made real, with the way back wired in ─────────
#
# ON A FRESH MACHINE this block does nothing: k3s was just installed
# and its first start already read the drop-in. It exists for the other
# case, which is the common one -- an instance that already exists,
# where install-k3s.yml is a no-op because the version matches, k3s
# never restarts, and the drop-in sits there changing nothing while
# looking perfectly applied.
#
# THE VALVE IS NOT OPTIONAL. A malformed kubelet-arg stops k3s from
# starting at all, and a node is worth more than a reservation. So:
# restart, wait a bounded time for the node to answer, and if it does
# not, take the drop-in back out, restart again, and die saying so.
#
# Over-reserving is a different and much softer failure -- pods go
# Pending and get evicted, the node stays up -- and it is deliberately
# NOT what this rolls back. That one is visible in `aegis host budget`,
# and phase 87 has its own gate that refuses to deploy into it.
if [[ -n "$AEGIS_NODE_RESERVED" ]] \
   && [[ "$AEGIS_NODE_RESERVED" != "$AEGIS_RESERVED_WAS" ]] \
   && sudo -n systemctl is-active --quiet k3s 2>/dev/null; then
    log_warn "the node's reservation changed: restarting k3s (the cluster is unreachable for a few seconds)"
    run_cmd sudo systemctl restart k3s
    # THE LABEL IS THE THIRD ARGUMENT. `wait_for TIMEOUT EVERY WHAT
    # cmd...` consumes three before the command, and the first draft
    # passed `kubectl` as the label -- so the command it actually
    # polled was `get --raw=/readyz`, which is not a command. It never
    # succeeded, the valve fired after 180 s, and a reservation that
    # was working perfectly was rolled back. Measured 2026-09-10, on
    # this machine, with the cluster healthy the whole time.
    #
    # A valve whose probe can only say NO is not a safety net; it is a
    # switch that turns the feature off on a timer.
    if wait_for 180 5 "the API to answer after the restart" \
            _k3s_api_answers; then
        log_info "k3s came back with the reservation in place"
    else
        log_warn "k3s did not answer in 180 s -- taking the reservation back out"
        sudo -n rm -f "$AEGIS_RESERVED_FILE"
        # NOT `|| true` on either of these, and the distinction is the
        # one check 009 exists to protect: `|| true` DISCARDS a result,
        # and on a path that is already dying the last thing an
        # operator needs is a rollback that failed in silence. Both
        # outcomes are reported; neither aborts the rollback, because
        # the `die` below is going to run whatever happens.
        sudo systemctl restart k3s \
            || log_warn "the restart WITHOUT the reservation also failed: read 'systemctl status k3s'"
        wait_for 180 5 "the API to answer without the reservation" \
                _k3s_api_answers \
            && log_info "the node came back once the reservation was withdrawn" \
            || log_warn "the node did not come back even without the reservation: the cause is NOT this drop-in"
        die "the node did not come back with the reservation, so it was withdrawn and k3s restarted without it.
  The rejected drop-in is what 'aegis host reservation --for kubelet' prints.
  The node is running WITHOUT a reservation: it hands out the whole machine until this is resolved."
    fi
fi

# ── the GPU runtime, measured where it becomes true ────────────────
# The toolkit was installed above, before k3s existed, precisely so
# that k3s would write its containerd config with the `nvidia` handler
# in it. That is a CONSEQUENCE, so it is measured here and not assumed
# there: an apt package that installed fine and a containerd that never
# saw it look identical from the playbook's side.
#
# Reading the generated config and not `nvidia-ctk --version`: the
# question is not whether the binary exists, it is whether the runtime
# k3s will hand to a Pod with `runtimeClassName: nvidia` exists. On an
# instance that was already installed and later switched to AI=gpu,
# this comes out RED and its diagnosis says to restart k3s — red and
# noisy is exactly what that case deserves.
# EVERY read of that path goes through sudo, the existence test
# included. Measured on the first live run, 2026-08-31: the directory
# is root-only (drwx------), so an unprivileged `[[ -f ]]` answers NO
# about a file that is right there. The grep below already used sudo
# and would have found the handler; the test in front of it did not,
# so the gate never reached its subject and reported a failure about a
# host that was correctly configured.
#
# It is the same class as the export that copied nothing in August: a
# privileged path probed from an unprivileged shell. There the shell
# said success and did nothing; here it said failure and measured
# nothing. Both are an instrument that never touched what it judged.
_k3s_containerd_conf() {
    local f
    for f in /var/lib/rancher/k3s/agent/etc/containerd/config.toml \
             /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml; do
        sudo -n test -f "$f" && { printf '%s' "$f"; return 0; }
    done
    return 1
}
if [[ "$AI" == "gpu" ]]; then
    _nvidia_runtime_present() {
        local f; f="$(_k3s_containerd_conf)" || return 1
        sudo -n grep -qE 'runtimes\.nvidia|nvidia-container-runtime' "$f"
    }
    gate_diag "nvidia-runtime-in-containerd" \
      'echo "  k3s writes its containerd config at start-up, DETECTING the runtimes";
       echo "  it finds on the PATH. If this is red, one of two things happened:";
       echo "    - nvidia-container-toolkit did not install (read the playbook output), or";
       echo "    - this host already had k3s and it has not restarted since:";
       echo "      sudo systemctl restart k3s, then aegis init --from 20";
       echo "  Nothing here edits that file by hand: k3s regenerates it on every";
       echo "  boot, so an edit would be erased and the drift would be silent."' \
      _nvidia_runtime_present
else
    gate_no_subject "nvidia-runtime-in-containerd" \
      "AI=$AI: this instance deploys no GPU engines, so no container runtime for the card is installed and there is nothing to measure. It is NOT that the runtime is fine — it is that this lane does not use one"
fi

# ── kubeconfig: copy AND verify the target (A11) ───────────────────
run_cmd mkdir -p "$HOME/.kube"
# with --write-kubeconfig-mode 600 (group_vars) the source is
# root:root 600, so a user-level `cp` can NO longer read it: the copy
# goes with privilege and in ONE step leaves both owner and mode
# right. The two sides are coupled on purpose — changing one without
# the other breaks the phase (check 85).
run_cmd sudo install -m 600 -o "$(id -u)" -g "$(id -g)" \
    /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
gate "kube-context" check_kube_context "$KUBE_CONTEXT_EXPECTED"

# ── the GPU label, the switch the device plugin obeys ──────────────
# k8s/base/gpu ships with every instance (core.yaml) and its DaemonSet
# carries `nodeSelector: aegis.dev/gpu=true`: the node says whether it
# has a card, and the plugin only lands where it does. Converges in
# both directions, so an instance that turns AI off later stops running
# a plugin that can never start.
if [[ "$AI" == "gpu" ]]; then
    run_cmd kubectl label node --all --overwrite aegis.dev/gpu=true
    gate "gpu-node-labelled" bash -c \
        '[[ -n "$(kubectl get nodes -l aegis.dev/gpu=true -o name 2>/dev/null)" ]]'
else
    run_cmd kubectl label node --all aegis.dev/gpu- 2>/dev/null
    gate_no_subject "gpu-node-labelled" \
        "AI=$AI: no node is labelled for the GPU on purpose, so the device plugin wants zero pods here and there is nothing to measure"
fi

# ── hetzner profile: Cilium BEFORE any NetworkPolicy (1.2b,
#    ADR-0014: k3s' default netpol controller does not enforce) ─────
if [[ "$PROFILE" == "hetzner" ]]; then
    # pin from group_vars; the factory value is a sentinel that FORCES
    # verifying it against the official chart before the first hetzner
    # run (rule: the real binary/chart, not memory):
    CILIUM_VER="$(python3 -c "import yaml; \
print(yaml.safe_load(open('ansible/inventory/group_vars/all.yml'))['cilium_chart_version'])")"
    [[ "$CILIUM_VER" == VERIFICAR* ]] && die \
        "unverified cilium pin in group_vars — fix it against helm.cilium.io before the hetzner profile"
    run_cmd helm repo add cilium https://helm.cilium.io --force-update
    run_cmd helm upgrade --install cilium cilium/cilium \
        --version "$CILIUM_VER" -n kube-system \
        --set operator.replicas=1
    gate "cilium-ready" bash -c \
      "kubectl -n kube-system rollout status ds/cilium --timeout=300s >/dev/null"

    # POSITIVE enforcement (A-netpol, 2026-06-20: kube-router accepted
    # the manifest and never populated the ipset — the manifest is NOT
    # evidence). Baseline first: with no policy the curl MUST pass (if
    # not, the "blocked" afterwards would prove breakage, not
    # enforcement):
    # P3 audit: the probe was not idempotent — a re-run with the
    # surviving ns died at the create. Clean up first (waiting for the
    # Terminating: a create against a dying ns fails too):
    run_cmd kubectl delete ns netpol-probe --ignore-not-found --wait=true
    run_cmd kubectl create ns netpol-probe
    run_cmd kubectl -n netpol-probe run target --image=nginx:alpine --port=80
    run_cmd kubectl -n netpol-probe expose pod target --port=80
    run_cmd kubectl -n netpol-probe wait --for=condition=Ready pod/target --timeout=120s
    probe_reset netpol-probe probe-open   # P1.8: --rm + retry cancels itself out
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

# ── unprivileged user namespaces (run #8, bug D) ───────────────────
# The buildah pod (proven green on v1/WSL2) needs rootless userns;
# Ubuntu >= 23.10 blocks it by default (apparmor). bootstrap-host
# relaxed the sysctl — this gate EXERCISES it (a real unshare as an
# unprivileged user) so that the verdict arrives HERE, not at the
# first build of phase 50 with a cryptic "permission denied":
gate "userns-sin-privilegios" unshare --user --map-root-user true

# ── default storageclass (1.2c) ────────────────────────────────────
# session 23 sweep (convergence family, the twin of coredns/H4 that
# had NOT bitten yet): local-path is created by the SAME async
# manifests controller as coredns — the single-shot could run before
# the SC exists. Existence→measurement:
gate "default-storageclass" wait_for 180 5 \
    "default StorageClass (local-path async, same controller as coredns)" \
    check_default_storageclass

# ── smoke ──────────────────────────────────────────────────────────
gate "nodos-ready" bash -c \
  "kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null"
# THE gate that used to knock phase 20 down on a mobile network (E-1):
# k3s' first boot pulls coredns/local-path/metrics from docker.io and
# a 120s timeout turned SLOW into FAILURE (the re-run "worked" because
# the pull was cached). wait_rollout: a generous wait with periodic
# evidence (which pod is Pulling/BackOff) — slow ≠ mute ≠ failure:
gate "coredns-vivo" wait_rollout kube-system deploy/coredns 900

log_ok "K3s alive, kubeconfig verified, default storage present"
