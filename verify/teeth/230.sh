# teeth of check 230 — the valve's probe.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
PH230="$AEGIS_ROOT/init/phases/20-k3s.sh"

# the probe as it was on 2026-09-22: kubectl with a kubeconfig that this
# phase has not written yet
red_1() { _sub "$PH230" '    sudo -n env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get --raw=/readyz >/dev/null 2>&1 \
        || kubectl get --raw=/readyz >/dev/null 2>&1' '    kubectl get --raw=/readyz >/dev/null 2>&1'; }

# only sudo: a machine where sudo -n is refused loses the probe
red_2() { _sub "$PH230" '        || kubectl get --raw=/readyz >/dev/null 2>&1' '        || false'; }

# a probe that always says yes: the valve can no longer save the node
red_3() { _sub "$PH230" '    sudo -n env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get --raw=/readyz >/dev/null 2>&1 \
        || kubectl get --raw=/readyz >/dev/null 2>&1' '    true'; }

# control: the same two attempts, written with the fallback first
control_1() { _sub "$PH230" '    sudo -n env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get --raw=/readyz >/dev/null 2>&1 \
        || kubectl get --raw=/readyz >/dev/null 2>&1' '    kubectl get --raw=/readyz >/dev/null 2>&1 \
        || sudo -n env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get --raw=/readyz >/dev/null 2>&1'; }
