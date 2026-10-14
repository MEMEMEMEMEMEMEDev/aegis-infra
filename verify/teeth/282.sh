# teeth of check 282 — phase 80 says why the canary keeps its public bases
# (the Ubuntu lab VM, 2026-10-13).
P282="$AEGIS_ROOT/init/phases/80-supply-chain.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# phase 80 as on 2026-10-13: the bare assignment that set -e ends
red_1() { _sub "$P282" '    _GOLANG="$(_canary_from golang)" || _GOLANG=""' '    _GOLANG="$(_canary_from golang)"'; }
# the other base, the same death
red_2() { _sub "$P282" '    _ALPINE="$(_canary_from alpine)" || _ALPINE=""' '    _ALPINE="$(_canary_from alpine)"'; }
# going on in silence
red_3() { _sub "$P282" '        log_warn "the mirror does not serve golang/alpine yet' '        : log_warn "the mirror does not serve golang/alpine yet'; }
# the repoint that points at nothing
red_4() { _sub "$P282" '            -e "s|^FROM ([^ ]*/)?golang:[^ ]*|FROM $_GOLANG|" \' '            -e "s|^FROM ([^ ]*/)?nothing:[^ ]*|FROM $_GOLANG|" \'; }
# the pattern as on 2026-10-13: only the public FROM, a resume keeps the stale internal digest
red_5() { _sub "$P282" '            -e "s|^FROM ([^ ]*/)?golang:[^ ]*|FROM $_GOLANG|" \' '            -e "s|^FROM docker\\.io/library/golang:[^ ]*|FROM $_GOLANG|" \'; }

# ── controls ──
# the comment over it is words
control_1() { _sub "$P282" "    # \`|| …=\"\"\`: under set -e a bare assignment" "    # \`|| …=\"\"\`: with set -e on, a bare assignment"; }
