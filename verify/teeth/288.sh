# teeth of check 288 — the pinned charts render with the seed's values.
#
# WHAT THESE NEED. The check has a subject only under --with-charts, with
# helm installed and the chart repositories reachable: every mutation
# below is one more fetch and render of the thirteen charts. Run them as
#   aegis verify --teeth 288 --with-charts
# (the tooth runner carries the flag into every mutation). Without the
# flag, or without helm, the check skips, the runner reports «no subject
# — its teeth do not apply here», and nothing here is exercised: that is
# the declared third outcome, not a green. The two skip paths are
# environment, not tree, and are exercised by running the check with
# AEGIS_VERIFY_WITH_CHARTS=false and with a PATH that carries no helm.
A288="$AEGIS_ROOT/seed/platform/k8s/base/platform/argocd/values.yaml"
T288="$AEGIS_ROOT/seed/platform/k8s/base/ingress/traefik/values.yaml"
APPS288="$AEGIS_ROOT/seed/platform/k8s/argocd-apps"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the configs.cm bug as it was: the key leaves the values file and the
# chart renders happily without it
red_1() { _sub "$A288" '    server.insecure: true' '    server-insecure: true'; }

# run #5 finding B: the Service type the chart ignores, an eternal
# LoadBalancer <pending>
red_2() { _sub "$T288" '    type: ClusterIP' '    type: LoadBalancer'; }

# a pin that does not exist in the repository (the «pin invented from
# memory» class, twice in this project's history)
red_3() {
    local f
    f="$(grep -l 'chart: trivy$' "$APPS288"/*.yaml | head -1)"
    [[ -n "$f" ]] || return 1
    _sub "$f" "targetRevision: 0.24.0" "targetRevision: 0.24.999"
}

# ── controls ──
control_1() { printf '\n# a comment on the values, which renders nothing\n' >> "$A288"; }
control_2() { _sub "$T288" '# traefik 40.3.0 v2 values. A31 baked in: trustedIPs of the /16 pod' '# traefik 40.3.0 v2 values; A31 baked in: trustedIPs of the /16 pod'; }
