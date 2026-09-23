# teeth of check 233 — the device plugin, only where there is a card.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
DS233="$AEGIS_ROOT/seed/platform/k8s/base/gpu/device-plugin.yaml"
PH233="$AEGIS_ROOT/init/phases/20-k3s.sh"

# the DaemonSet as it shipped until 2026-09-23: every node, card or not
red_1() { _sub "$DS233" '      nodeSelector:
        aegis.dev/gpu: "true"
' ''; }

# the label never put on: the instance WITH a card loses its plugin
red_2() { _sub "$PH233" '    run_cmd kubectl label node --all --overwrite aegis.dev/gpu=true' '    :'; }

# the label never taken off: AI turned off keeps a plugin that cannot start
red_3() { _sub "$PH233" '    run_cmd kubectl label node --all aegis.dev/gpu- 2>/dev/null' '    :'; }

# the gate under AI=no/cpu vanishes instead of being declared
red_4() { _sub "$PH233" '    gate_no_subject "gpu-node-labelled" \' '    : "gpu-node-labelled" \'; }

# control: the same selector written in flow style
control_1() { _sub "$DS233" '      nodeSelector:
        aegis.dev/gpu: "true"
' '      nodeSelector: {aegis.dev/gpu: "true"}
'; }
