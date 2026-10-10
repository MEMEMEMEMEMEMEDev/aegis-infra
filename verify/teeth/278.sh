# teeth of check 278 — the ArgoCD admin password comes from the store (#86).
P30="$AEGIS_ROOT/init/phases/30-argocd.sh"
P35="$AEGIS_ROOT/init/phases/35-gitops.sh"
L278="$AEGIS_ROOT/lib/access.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the instance as it was born until 2026-10-10: the installer's password
red_1() { _sub "$P30" 'ARGO_ADMIN="$(gen_or_restore argocd_admin_pass gen_password_b64)"' 'ARGO_ADMIN="$SECRETS_TMP/argocd_admin_pass"'; }

# the password in argv
red_2() { _sub "$P30" '    htpasswd -nBi -C 10 admin < "$ARGO_ADMIN" | head -n1' '    htpasswd -nbB -C 10 admin "$(cat "$ARGO_ADMIN")" | head -n1'; }

# re-patched on every run: every session closed each time the phase runs
red_3() { _sub "$P30" 'if [[ "$ARGO_LIVE_MARK" != "$ARGO_MARK" ]]; then' 'if true; then'; }

# the installer's Secret stays
red_4() { _sub "$P30" 'run_cmd kubectl -n argocd delete secret argocd-initial-admin-secret --ignore-not-found >/dev/null
' ''; }

# the negative half: an ArgoCD that accepts anything comes out green
red_5() { _sub "$L278" '    if [[ "$code_bad" != 401 ]]; then' '    if false; then'; }

# the positive half
red_6() { _sub "$L278" '    if [[ "$code_ok" != 200 ]]; then' '    if false; then'; }

# measured only on the cloudflare edge
red_7() { _sub "$P35" '        gate "argocd-admin-entra" retry_net 3 argocd_admin_login_ok "https://argocd.$ROOT_DOMAIN"
        unset CURL_CA_BUNDLE' '        unset CURL_CA_BUNDLE'; }

# polled: the account locks itself out
red_8() { _sub "$P35" '    gate "argocd-admin-entra" retry_net 3 argocd_admin_login_ok "https://argocd.$ROOT_DOMAIN"

' '    gate "argocd-admin-entra" poll 300 10 argocd_admin_login_ok "https://argocd.$ROOT_DOMAIN"

'; }

# rotation still sends it to the manual path
red_9() { _sub "$AEGIS_ROOT/libexec/aegis-rotate" 'argocd_admin_pass|normal|30-argocd|' 'argocd_admin_pass|manual|-|'; }

# ── controls ──
control_1() { _sub "$P30" 'ArgoCD admin password set from the store (argocd_admin_pass)' 'ArgoCD admin password taken from the store (argocd_admin_pass)'; }
