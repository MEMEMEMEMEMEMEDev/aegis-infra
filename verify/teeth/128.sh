# teeth for check 128 (the console is not published at the edge)
#
# Both reds are somebody being helpful: publishing the console so it can
# be reached from a phone. Neither fails anywhere — the first produces a
# hostname that resolves, gets a certificate, and answers 404 forever;
# the second puts the whole round on the LAN.

red_1() { sed -i 's/^  - aegis$/  - aegis\n  - console/' "$AEGIS_ROOT/seed/platform/edge.yaml"; }

red_2() { python3 - "$AEGIS_ROOT/libexec/aegis-console" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('sv.add_argument("--port", type=int, default=7391,',
              'sv.add_argument("--bind", default="0.0.0.0")\n    sv.add_argument("--port", type=int, default=7391,')
p.write_text(s)
P
}

# ── controls ─────────────────────────────────────────────────────────

# a new door for something that DOES live in the cluster: the platform
# is allowed to publish things, just not this one
control_1() { sed -i 's/^  - aegis$/  - aegis\n  - registry/' "$AEGIS_ROOT/seed/platform/edge.yaml"; }

# the port becomes configurable, which is fine: the port is not the
# address, and nothing about it changes who can reach the page
control_2() { sed -i 's/default=7391,/default=8080,/' "$AEGIS_ROOT/libexec/aegis-console"; }

# prose that names the forbidden shape right next to the code
control_3() { printf '\n# note: publishing this at the edge would need a connector on the host\n# and a tunnel of its own; the cluster connector cannot reach 127.0.0.1.\n' >> "$AEGIS_ROOT/libexec/aegis-console"; }
