# teeth of check 246 — traefik does not hang the visitor on a dead backend.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
TRA246="$AEGIS_ROOT/seed/platform/k8s/base/ingress/traefik/values.yaml"

# traefik as it was on 2026-09-24: no timeouts at all
red_1() { _sub "$TRA246" 'additionalArguments:
  - "--serversTransport.forwardingTimeouts.dialTimeout=5s"
  - "--serversTransport.forwardingTimeouts.responseHeaderTimeout=60s"
' ''; }

# the header wait back to its default: forever
red_2() { _sub "$TRA246" 'responseHeaderTimeout=60s' 'responseHeaderTimeout=0s'; }

# a header wait Cloudflare outlasts: its 524 lands first
red_3() { _sub "$TRA246" 'responseHeaderTimeout=60s' 'responseHeaderTimeout=120s'; }

# the dial back to its default
red_4() { _sub "$TRA246" 'dialTimeout=5s' 'dialTimeout=30s'; }

# control: the same values, spelled the way traefik's --help prints them
control_1() { _sub "$TRA246" '"--serversTransport.forwardingTimeouts.dialTimeout=5s"' '"--serverstransport.forwardingtimeouts.dialtimeout=5s"'; }
