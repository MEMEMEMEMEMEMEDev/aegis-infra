# teeth for 226 — each red brings back one of the four small lies.
K226="$AEGIS_ROOT/libexec/aegis-check"
R226="$AEGIS_ROOT/libexec/state/restore"
T226="$AEGIS_ROOT/libexec/aegis-rotate"
_s226() { python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}
# the round goes back to 0 or 1: could-not-look is a notice again
red_1() { _s226 "$K226" 'if [[ ${noteval:-0} -gt 0 ]]; then' 'if false; then'; }
# 1 before 2: a failure hides the unmeasured section
red_2() { python3 - "$K226" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
a = s.index("if [[ ${noteval:-0} -gt 0 ]]; then"); b = s.index("if [[ $failures -gt 0 ]]; then\n    printf '%s%d failure(s)%s, %d notice(s)\\n'"); c = s.index("printf '%sno failures%s")
block2, block1 = s[a:b], s[b:c]
p.write_text(s[:a] + block1 + block2 + s[c:])
PY
}
# the notice stops counting
red_3() { _s226 "$K226" '_rec not-evaluated "$*"; noteval=$((noteval + 1)) ;;' '_rec not-evaluated "$*" ;;'; }
# the AppProject measure is gone
red_4() { _s226 "$K226" '    if kubectl get appproject "aegis-tenant-$_o" -n argocd >/dev/null 2>&1; then' '    if true; then'; }
# restore reads --force as the second word again
red_5() { python3 - "$R226" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index('BUNDLE=""; FORCE=0'); j = s.index('[[ -n "$BUNDLE" && -f "$BUNDLE" ]]')
p.write_text(s[:i] + 'BUNDLE="${1:-}"; FORCE=0\n[[ "${2:-}" == "--force" ]] && FORCE=1\n' + s[j:])
PY
}
# rotate loses its help block
red_6() { _s226 "$T226" "# aegis-help:
# Usage: aegis rotate list" "# aegis-notes:
# Usage: aegis rotate list"; }
# ── controls ──
control_1() { _s226 "$K226" "# 2 DOMINATES 1: a round that could not take a measure has not" "# 2 dominates 1: an unmeasured round has not"; }
control_2() { _s226 "$T226" "# continue  resumes the last batch where it stopped." "# continue  resumes the last batch where it stopped (reads the journal)."; }
