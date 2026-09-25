# teeth of check 244 — per-visitor limiters and a door with room.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
ORG244="$AEGIS_ROOT/lib/aegis/org.py"
CAN244="$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml"
TRA244="$AEGIS_ROOT/seed/platform/k8s/base/ingress/traefik/values.yaml"

# the generator as it was until 2026-09-24: no criterion, one bucket for everybody
red_1() { _sub "$ORG244" '    sourceCriterion:
      ipStrategy:
        excludedIPs: ["10.42.0.0/16"]
    average: 50                     # sustained req/s per visitor' '    average: 50                     # sustained req/s per visitor'; }

# the seed's canary without it
red_2() { _sub "$CAN244" '    sourceCriterion:
      ipStrategy:
        excludedIPs: ["10.42.0.0/16"]
' ''; }

# a range that is not the one the entrypoints trust (the service CIDR by mistake)
red_3() { _sub "$ORG244" 'excludedIPs: ["10.42.0.0/16"]' 'excludedIPs: ["10.43.0.0/16"]'; }

# traefik back to one replica
red_4() { _sub "$TRA244" '  replicas: 2' '  replicas: 1'; }

# traefik back to the memory it died with
red_5() { _sub "$TRA244" 'limits: {cpu: "1", memory: 512Mi}' 'limits: {cpu: "1", memory: 256Mi}'; }

# control: the same criterion, written as a flow list
control_1() { _sub "$CAN244" '    sourceCriterion:
      ipStrategy:
        excludedIPs: ["10.42.0.0/16"]' '    sourceCriterion: {ipStrategy: {excludedIPs: [10.42.0.0/16]}}'; }
