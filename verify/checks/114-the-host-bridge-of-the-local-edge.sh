# title: the host bridge of the local edge: shipped, installed, bounded and removable
# origin: new in v3 — T-04a (2026-08-26), the local edge
check() {
# With EDGE=local there is no tunnel and no zone: what hands ports 80
# and 443 of the HOST to traefik is a bridge of systemd sockets. It is
# the only piece of the platform that lives OUTSIDE the cluster and
# outside the repo, which means every habit this verifier relies on
# stops applying to it — no Application declares it, no kustomize
# builds it, and ArgoCD would never notice it gone.
#
# So this check watches the four things that make the bridge either
# right or quietly wrong:
#
#   (a) it is SHIPPED: the units are versioned artifacts and not a
#       heredoc buried in a phase, so they can be read and diffed;
#   (b) it is BOUNDED: what ships listens on loopback, and reaching
#       further is an explicit decision of the operator;
#   (c) the RESET: the drop-in that changes the address begins with an
#       empty `ListenStream=`. This is the subtle one and the reason
#       this check exists. In systemd a drop-in that repeats a list
#       directive ADDS to it; only the empty assignment clears it. Take
#       that one line away and the bridge listens on the chosen address
#       AND on loopback — every unit valid, every gate green, and a
#       listening surface nobody asked for;
#   (d) it is REMOVABLE: `aegis destroy` knows about it. A teardown that
#       leaves the bridge behind leaves the host holding 80 and 443 for
#       a cluster that no longer exists, and hands the next init the
#       dirtiest possible starting point.
D114=""
SYSD="$AEGIS_ROOT/share/systemd"
P25="$PHASES/25-edge-tofu.sh"
DESTROY="$LIBEXEC/aegis-destroy"

[[ -d "$SYSD" ]] || { fail "share/systemd does not exist: the local edge has no bridge to install"; return; }

# ── (a) the four units, shipped ─────────────────────────────────────
for u in aegis-edge-http.socket aegis-edge-http.service \
         aegis-edge-https.socket aegis-edge-https.service; do
    [[ -f "$SYSD/$u" ]] || D114="$D114 share/systemd/$u is missing;"
done

# ── (b) what ships listens on loopback, and only on loopback ────────
for pair in http:80 https:443; do
    s="aegis-edge-${pair%%:*}.socket" ; port="${pair##*:}"
    [[ -f "$SYSD/$s" ]] || continue
    LS="$(grep -c '^ListenStream=' "$SYSD/$s")"
    (( LS == 1 )) || D114="$D114 $s declares $LS ListenStream (it has to be exactly one: the address is chosen by the operator, not accumulated);"
    grep -q "^ListenStream=127\.0\.0\.1:$port\$" "$SYSD/$s" \
        || D114="$D114 $s does not ship bound to 127.0.0.1:$port — what ships must not reach beyond this host;"
done

# The proxy reads WHERE to forward from a file, not from a baked-in
# address: re-pointing the bridge has to be editing one line, and a
# ClusterIP baked into a unit is a bridge that lies after a re-install.
for pair in http:80 https:443; do
    v="aegis-edge-${pair%%:*}.service" ; port="${pair##*:}"
    [[ -f "$SYSD/$v" ]] || continue
    grep -q '^EnvironmentFile=/etc/aegis/edge.env$' "$SYSD/$v" \
        || D114="$D114 $v does not read /etc/aegis/edge.env: the upstream would be baked into the unit;"
    grep -qE '^ExecStart=.*systemd-socket-proxyd .*\$\{AEGIS_EDGE_UPSTREAM\}:'"$port"'$' "$SYSD/$v" \
        || D114="$D114 $v does not forward \${AEGIS_EDGE_UPSTREAM}:$port;"
done

# ── the phase installs it, and only under the edge that needs it ────
if [[ ! -f "$P25" ]]; then
    D114="$D114 phase 25 does not exist: nobody installs the bridge;"
else
    P25_NC="$(nc "$P25")"
    echo "$P25_NC" | grep -q 'EDGE.*local' \
        || D114="$D114 phase 25 does not branch on EDGE: it would install the bridge on an edge that does not want it;"
    echo "$P25_NC" | grep -q '/etc/aegis/edge.env' \
        || D114="$D114 phase 25 does not write /etc/aegis/edge.env: the proxy has no upstream to read;"
    for s in aegis-edge-http.socket aegis-edge-https.socket; do
        echo "$P25_NC" | grep -q "$s" \
            || D114="$D114 phase 25 never names $s: half a bridge holds one port and drops the other;"
    done
    echo "$P25_NC" | grep -q 'systemctl.*enable' \
        || D114="$D114 phase 25 does not enable the sockets: the bridge would not survive a reboot;"

    # ── (c) THE RESET ───────────────────────────────────────────────
    # The empty ListenStream= has to come BEFORE the concrete one, in
    # the same block. Order is the whole property: an empty assignment
    # after the value clears what was just set.
    if ! echo "$P25_NC" | grep -q 'ListenStream=$'; then
        D114="$D114 the bind drop-in has NO empty ListenStream=: systemd ADDS to a list directive instead of replacing it, so the bridge would listen on the chosen address AND on loopback — every unit valid and a listening surface nobody asked for;"
    else
        RESET_LN="$(echo "$P25_NC" | grep -n 'ListenStream=$' | head -1 | cut -d: -f1)"
        VALUE_LN="$(echo "$P25_NC" | grep -n 'ListenStream=\$EDGE_BIND_IP' | head -1 | cut -d: -f1)"
        if [[ -z "$VALUE_LN" ]]; then
            D114="$D114 the drop-in never writes ListenStream=\$EDGE_BIND_IP: the operator's address is not applied;"
        elif (( RESET_LN >= VALUE_LN )); then
            D114="$D114 the empty ListenStream= comes AFTER the concrete one: it clears the address instead of the default;"
        fi
    fi

    # ── one source of truth for the upstream ────────────────────────
    # The address the phase writes has to be traefik's FIXED ClusterIP
    # in the seed. Two places holding that number is how a bridge ends
    # up pointing at a Service that moved.
    TV="$SEED/platform/k8s/base/ingress/traefik/values.yaml"
    if [[ -f "$TV" ]]; then
        CIP="$(sed -n 's/^[[:space:]]*clusterIP:[[:space:]]*\([0-9.]*\).*/\1/p' "$TV" | head -1)"
        if [[ -z "$CIP" ]]; then
            D114="$D114 traefik's values declare no fixed clusterIP: the bridge has no stable address to forward to;"
        elif ! echo "$P25_NC" | grep -q "$TV\|clusterIP\|traefik"; then
            D114="$D114 phase 25 does not read traefik's ClusterIP from its values: the upstream would be a second copy of that number;"
        fi
    fi
fi

# ── (d) the teardown knows about it ─────────────────────────────────
if [[ ! -f "$DESTROY" ]]; then
    D114="$D114 aegis-destroy does not exist;"
else
    D_NC="$(nc "$DESTROY")"
    echo "$D_NC" | grep -q 'aegis-edge-http.socket' \
        || D114="$D114 aegis-destroy does not stop the bridge's sockets: after a teardown the host keeps holding 80 and 443 for a cluster that is gone;"
    echo "$D_NC" | grep -q '/etc/aegis/edge.env' \
        || D114="$D114 aegis-destroy does not remove /etc/aegis/edge.env;"
    echo "$D_NC" | grep -q 'daemon-reload' \
        || D114="$D114 aegis-destroy removes units without a daemon-reload: systemd would keep the removed ones loaded;"
fi

printf '    4 units, the bind reset, one upstream and the teardown\n'
if [[ -n "$D114" ]]; then fail "the host bridge:$D114"
else pass "the bridge ships bound to loopback, reads its upstream from a file, resets the bind list before rebinding, and aegis-destroy takes it down"; fi
}
