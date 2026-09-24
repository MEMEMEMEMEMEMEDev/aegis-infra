# teeth of check 237 — the canary sync ArgoCD does not retry.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
PH237="$AEGIS_ROOT/init/phases/80-supply-chain.sh"

# the phase as it was on 2026-09-24: it notices and does nothing
red_1() { _sub "$PH237" '    argo_sync hello-aegis 300
fi' '    :
fi'; }

# any failure counts: a sync refusing an unsigned image is re-fired into the same denial
red_2() { _sub "$PH237" '             and ((.status.operationState.message // "") | contains($d))'"'"' >/dev/null' '             or ((.status.operationState.message // "") | contains($d))'"'"' >/dev/null'; }

# the digest ignored: every failed sync is re-fired
red_3() { _sub "$PH237" "'.status.operationState.phase == \"Failed\"" "'.status.operationState.phase != \"Succeeded\""; }

# control: the same condition, the log worded differently
control_1() { _sub "$PH237" '(before Kyverno could verify it) — syncing it again' '(Kyverno could not verify it then) — firing the sync again'; }
