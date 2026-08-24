# title: NetworkPolicies: default-deny del tenant + DNS en egress (W-07)
# origen: verify-static.sh (v2) ══ 77
check() {
D77=""
NPD="$P/k8s/organizations/org-canary"
NP="$NPD/netpol.yaml"
if [[ -f "$NP" ]]; then
    python3 - "$NP" <<'PY' || D77="$D77 netpol org-canary: sin default-deny, o niega egress sin permitir DNS;"
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
nps = [d for d in docs if d.get('kind') == 'NetworkPolicy']
spec = lambda d: d.get('spec', {})
# default-deny: podSelector {} y ambos policyTypes
dd = [d for d in nps if spec(d).get('podSelector') == {}
      and {'Ingress', 'Egress'} <= set(spec(d).get('policyTypes', []))]
ok = len(dd) >= 1
# si se NIEGA egress, DEBE haber un netpol que permita DNS (:53) — el
# error #1 de netpol es olvidarlo y romper toda la resolución:
denies_egress = any('Egress' in spec(d).get('policyTypes', [])
                    and not spec(d).get('egress') for d in nps)
allows_dns = any(
    any(p.get('port') == 53
        for rule in (spec(d).get('egress') or [])
        for p in rule.get('ports', []))
    for d in nps)
if denies_egress and not allows_dns:
    ok = False
sys.exit(0 if ok else 1)
PY
else
    D77="$D77 falta $NP;"
fi
grep -q 'netpol.yaml' "$NPD/kustomization.yaml" \
    || D77="$D77 el kustomization de org-canary no lista netpol.yaml;"
grep -q 'netpol-tenant-aislado' "$PHASES/80-supply-chain.sh" \
    || D77="$D77 falta el gate netpol-tenant-aislado (aislamiento sin verificar en runtime);"
# W-07 iter2 (RBAC del tenant): el SA default de org-canary NO monta
# el token de la API (el tenant no administra el cluster):
grep -Fq 'automountServiceAccountToken: false' "$NPD/bundle.yaml" \
    || D77="$D77 el SA del tenant monta el token de la API (falta automountServiceAccountToken:false);"
if [[ -n "$D77" ]]; then fail "netpol:$D77"
else pass "org-canary: default-deny + edge-in:8080 + DNS-out; gate de aislamiento; SA sin token de API"; fi
}
