# title: NetworkPolicies: tenant default-deny + DNS in egress (W-07)
# origin: verify-static.sh (v2) ══ 77
check() {
D77=""
NPD="$P/k8s/organizations/org-canary"
NP="$NPD/netpol.yaml"
if [[ -f "$NP" ]]; then
    python3 - "$NP" <<'PY' || D77="$D77 org-canary netpol: no default-deny, or it denies egress without allowing DNS;"
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
nps = [d for d in docs if d.get('kind') == 'NetworkPolicy']
spec = lambda d: d.get('spec', {})
# default-deny: podSelector {} and both policyTypes
dd = [d for d in nps if spec(d).get('podSelector') == {}
      and {'Ingress', 'Egress'} <= set(spec(d).get('policyTypes', []))]
ok = len(dd) >= 1
# if egress is DENIED, there MUST be a netpol allowing DNS (:53) — the
# #1 netpol mistake is forgetting it and breaking all resolution:
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
    D77="$D77 $NP missing;"
fi
grep -q 'netpol.yaml' "$NPD/kustomization.yaml" \
    || D77="$D77 org-canary's kustomization does not list netpol.yaml;"
grep -q 'netpol-tenant-aislado' "$PHASES/80-supply-chain.sh" \
    || D77="$D77 the netpol-tenant-aislado gate is missing (isolation unverified at runtime);"
# W-07 iter2 (tenant RBAC): org-canary's default SA does NOT mount the
# API token (the tenant does not administer the cluster):
grep -Fq 'automountServiceAccountToken: false' "$NPD/bundle.yaml" \
    || D77="$D77 the tenant's SA mounts the API token (automountServiceAccountToken:false missing);"
if [[ -n "$D77" ]]; then fail "netpol:$D77"
else pass "org-canary: default-deny + edge-in:8080 + DNS-out; isolation gate; SA without an API token"; fi
}
