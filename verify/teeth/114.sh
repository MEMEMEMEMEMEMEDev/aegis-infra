# teeth for check 114 (the host bridge of the local edge)
#
# The bridge lives outside the cluster and outside the repo: no
# Application declares it and ArgoCD would never notice it gone. These
# mutations are the four ways it breaks quietly.

# THE ONE THIS CHECK WAS BORN FOR: the empty ListenStream= disappears
# from the drop-in. In systemd a repeated list directive ADDS, so the
# bridge would listen on the chosen address AND on loopback — every
# unit valid, every gate green, a listening surface nobody asked for.
red_1() {
    python3 - "$AEGIS_ROOT/init/phases/25-edge-tofu.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "ListenStream=\nListenStream=$EDGE_BIND_IP:$_port\n"
assert old in t
open(p, "w").write(t.replace(old, "ListenStream=$EDGE_BIND_IP:$_port\n", 1))
PY
}

# the reset ends up AFTER the value, which clears the address instead
# of the default: the bridge would bind to nothing at all
red_2() {
    python3 - "$AEGIS_ROOT/init/phases/25-edge-tofu.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "ListenStream=\nListenStream=$EDGE_BIND_IP:$_port\n"
assert old in t
open(p, "w").write(t.replace(old, "ListenStream=$EDGE_BIND_IP:$_port\nListenStream=\n", 1))
PY
}

# what ships stops being bound to loopback: a checkout of the product
# would carry units that reach the whole network by default
red_3() {
    sed -i 's/^ListenStream=127\.0\.0\.1:80$/ListenStream=0.0.0.0:80/' \
        "$AEGIS_ROOT/share/systemd/aegis-edge-http.socket"
}

# the teardown forgets the bridge: after a destroy the host keeps
# holding 80 and 443 for a cluster that no longer exists
red_4() {
    python3 - "$AEGIS_ROOT/libexec/aegis-destroy" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert "/etc/aegis/edge.env" in t
open(p, "w").write(t.replace("/etc/aegis/edge.env", "/etc/aegis/nothing.env"))
PY
}

# the proxy gets its upstream baked in instead of read from the file:
# re-pointing the bridge would mean reinstalling the unit, and after a
# re-install it would forward to a Service that moved
red_5() {
    sed -i 's|^EnvironmentFile=/etc/aegis/edge.env$|# EnvironmentFile removed|' \
        "$AEGIS_ROOT/share/systemd/aegis-edge-http.service"
}

# control: hardening the proxy further is a legitimate change and must
# not turn the check red
control_1() {
    printf 'ProtectHostname=yes\n' >> "$AEGIS_ROOT/share/systemd/aegis-edge-http.service"
}

# control: telling the story in a comment, naming the very things the
# check greps for, is what this tree does everywhere
control_2() {
    printf '\n# history: this used to hold ListenStream= and /etc/aegis/edge.env\n' \
        >> "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
}
