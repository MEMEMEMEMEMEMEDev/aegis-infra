# teeth of check 253 — a stream piped into `grep -q` under pipefail.
J253="$AEGIS_ROOT/lib/jenkins.sh"
S253="$AEGIS_ROOT/lib/secrets.sh"
B253="$AEGIS_ROOT/libexec/state/backup"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the retry as it was on 2026-09-24 (H-05)
red_1() { _sub "$J253" '        if grep -qiE "$AEGIS_NET_SIGS" \
             < <(jenkins_get "/job/$(_jenkins_job "$job")/$next/consoleText" 2>/dev/null); then' '        if jenkins_get "/job/$(_jenkins_job "$job")/$next/consoleText" 2>/dev/null \
             | grep -qiE "$AEGIS_NET_SIGS"; then'; }

# the SOPS roundtrip piped again
red_2() { _sub "$S253" "    grep -q '^kind: Secret' < <(sops -d \"\$dest\") \\" "    sops -d \"\$dest\" | grep -q '^kind: Secret' \\"; }

# a pipe inside \$( ) inside double quotes is this shell's code too
red_3() { _sub "$J253" 'jenkins_build_retry() {
' 'jenkins_build_retry() {
    local _seen="$(jenkins_get "/job/x/api/json" 2>/dev/null | grep -qx y && echo y)"
'; }

# the age-key guard of the backup: find streams, the guard would read «no key»
red_4() { _sub "$B253" "if grep -q . < <(find \"\$PAY\" -type f" "if find \"\$PAY\" -type f"; sed -i "s#      -o -path '\*/sops/age/\*' 2>/dev/null); then#      -o -path '*/sops/age/*' 2>/dev/null | grep -q .; then#" "$B253"; }

# ── controls ──
# a `bash -c` string runs without pipefail: not this shell's pipe
control_1() { _sub "$J253" 'jenkins_build_retry() {
' 'jenkins_build_retry() {
    bash -c "kubectl get ns | grep -q default" || true
'; }
# a comment that shows the old form
control_2() { _sub "$J253" '        # into «no network signature» — half of the time (check 253).' '        # into «no network signature» — half of the time (check 253):
        #   jenkins_get … | grep -qiE "$AEGIS_NET_SIGS"   ← never again'; }
# a heredoc body is text
control_3() { printf '\n_doc253() { cat <<EOT\nkubectl get pods | grep -q Running\nEOT\n}\n' >> "$J253"; }
