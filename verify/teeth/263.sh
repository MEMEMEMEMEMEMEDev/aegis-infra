# teeth of check 263 — every command finds the age key from any directory.
B263="$AEGIS_ROOT/bin/aegis"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the dispatcher as it was: only direnv, in the instance directory, knew the key
red_1() { _sub "$B263" '    export SOPS_AGE_KEY_FILE="$_aegis_age_key"' '    :'; }

# an explicit key is overridden by the installed one
red_2() { _sub "$B263" 'if [[ ! -f "${SOPS_AGE_KEY_FILE:-/nonexistent}" && -f "$_aegis_age_key" ]]; then' 'if [[ -f "$_aegis_age_key" ]]; then'; }

# a key that does not exist is handed over anyway
red_3() { _sub "$B263" 'if [[ ! -f "${SOPS_AGE_KEY_FILE:-/nonexistent}" && -f "$_aegis_age_key" ]]; then' 'if [[ ! -f "${SOPS_AGE_KEY_FILE:-/nonexistent}" ]]; then'; }

# ── controls ──
control_1() { _sub "$B263" '# ── the instance'"'"'s age key, from ANY directory ───────────────────────' '# ── the age key of the instance, from ANY directory ───────────────────'; }
