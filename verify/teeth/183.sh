# teeth of check 183 — the tunnel is left with no connections before the
# teardown asks Cloudflare to delete it.

# THE STATE THE ARTIFACT WAS IN until 2026-09-02: nothing disconnected
# anything, and `destroy --yes --k3s` on a live instance died on
# «1022 active connections» with the edge already half destroyed.
red_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-destroy" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^    _disconnect_tunnel\n', '', s, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# it scales down and never takes ArgoCD's hand off the Application:
# selfHeal puts the replica back and the tunnel keeps its connections.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-destroy" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'\n  if kubectl -n argocd get application cloudflare-tunnel.*?\n  fi\n', s, re.S)
assert m, "the ArgoCD block could not be located"
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), "\n", 1))
PYEOF
}

# right operations, wrong order: by the time selfHeal is disabled,
# ArgoCD has already healed what was just scaled to zero.
red_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-destroy" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
argo = re.search(r'\n  if kubectl -n argocd get application cloudflare-tunnel.*?\n  fi\n', s, re.S).group(0)
escala = ('\n  say "edge: stopping cloudflared so the tunnel has no live connections"\n'
          '  kubectl -n infra-edge scale deploy cloudflared --replicas=0 >/dev/null 2>&1 || true\n')
assert s.count(escala) == 1
s = s.replace(argo, "\n", 1).replace(escala, escala + argo, 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# it asks for the deletion while the replica is still terminating: the
# same race that failed, only faster.
red_4() {
    python3 - "$AEGIS_ROOT/libexec/aegis-destroy" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'\n  local i\n  for i in \$\(seq 1 60\); do.*?\n  done\n', s, re.S)
assert m, "the wait loop could not be located"
open(p, "w", encoding="utf-8").write(s.replace(m.group(0), "\n", 1))
PYEOF
}

# no guard for a host whose cluster is already gone: a second teardown,
# or one after a manual k3s-uninstall, dies talking to nothing.
red_5() {
    sed -i 's|^  kubectl cluster-info >/dev/null 2>&1 \|\| return 0$|  true|' \
        "$AEGIS_ROOT/libexec/aegis-destroy"
}

# control: the PROSE that explains the whole decision, in the same file
# and in the same words. This check runs the function instead of reading
# it precisely so a paragraph cannot stand in for the order.
control_1() {
    cat >> "$AEGIS_ROOT/libexec/aegis-destroy" <<'EOF'

# note: the tunnel refuses to be deleted while cloudflared holds
# connections, and scaling to zero is undone by ArgoCD's selfHeal
# unless the Application's automated syncPolicy is removed first.
EOF
}

# control: one more read-only call inside the guard. Asking the cluster
# something extra is not a defect; the guarantee is about order.
control_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-destroy" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '  say "edge: stopping cloudflared so the tunnel has no live connections"\n'
assert s.count(anchor) == 1
extra = '  kubectl -n infra-edge get deploy cloudflared -o name >/dev/null 2>&1 || true\n'
open(p, "w", encoding="utf-8").write(s.replace(anchor, extra + anchor, 1))
PYEOF
}
