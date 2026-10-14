# teeth of check 284 — a secret that fails to generate stops the init.
S284="$AEGIS_ROOT/lib/secrets.sh"
C284="$AEGIS_ROOT/lib/common.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the product as it was until 2026-10-14: errexit stops at every `$( )`
red_1() { _sub "$C284" 'shopt -s inherit_errexit
' ''; }

# the store takes a 0-byte file as a secret
red_2() { _sub "$S284" '    [[ -s "$src" ]] || die "persist of $name refused: the material is EMPTY — the generator failed; nothing was written to the store"
' ''; }

# gen_hex32 trusts openssl: a rand that prints nothing is a 0-byte HMAC
red_3() { _sub "$S284" '    _gen_guard "$out" 64 "$1"
' ''; }

# the guard that only warns
red_4() { _sub "$S284" '(( n >= min )) || die "generation of $label produced' '(( n >= min )) || log_warn "generation of $label produced'; }

# the secrets lib sourced on its own (aegis rotate, the phases through
# common.sh — but also any command that sources it first) leaves the option off
red_5() { _sub "$S284" 'set -euo pipefail
shopt -s inherit_errexit   # errexit reaches $( ) too; the why is in common.sh (check 284)
' 'set -euo pipefail
'; }

# ── controls ──
control_1() { _sub "$C284" 'inherit_errexit makes `$( )` die where the parent' 'inherit_errexit makes `$( )` die wherever the parent'; }
control_2() { _sub "$S284" 'the material is EMPTY — the generator failed; nothing was written to the store' 'the material is EMPTY (the generator failed); nothing was written to the store'; }
