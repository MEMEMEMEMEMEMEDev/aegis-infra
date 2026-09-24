# teeth of check 236 — the Kyverno restart owed for the CA.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
PH236="$AEGIS_ROOT/init/phases/80-supply-chain.sh"

# the phase as it was on 2026-09-24: only the injecting run restarts
red_1() { _sub "$PH236" 'if [[ "$CA_INJECTED_THIS_RUN" == "true" || -n "$KYV_OWED" ]]; then' 'if [[ "$CA_INJECTED_THIS_RUN" == "true" ]]; then'; }

# the comparison inverted: a fresh pod is taken for a stale one and a stale one for fresh
red_2() { _sub "$PH236" '"$started" < "$written"' '"$written" < "$started"'; }

# the youngest pod decides: a rollout halfway reads as done
red_3() { _sub "$PH236" "| jq -r '[.items[].status.startTime] | min // empty')\"" "| jq -r '[.items[].status.startTime] | max // empty')\""; }

# the proof after the restart is gone
red_4() { _sub "$PH236" 'gate "kyverno-ca-cargada" _kyverno_ca_loaded' ':'; }

# control: the same measurement, the log worded differently
control_1() { _sub "$PH236" 'log_info "Kyverno controllers started before their CA was written:' 'log_info "Kyverno controllers older than the CA they mount:'; }
