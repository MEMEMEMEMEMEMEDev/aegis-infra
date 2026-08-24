# title: platform NetworkPolicies iter2: ingress-only + real delivery (W-07)
# origin: verify-static.sh (v2) ══ 79
check() {
# iter2 isolates the CONTROL PLANE (trivy/jenkins/argocd) by ingress. It does
# NOT include registry/kyverno/cert-manager/infra-edge: those go in iter3 with
# a run of their own (cluster-wide pull and admission = 🔴🔴; the doc
# 04-netpol-diseno.md §3 puts them last). Invariants this check nails down:
#  a) the 3 netpols exist, with default-deny INGRESS;
#  b) INGRESS-ONLY — no netpol declares Egress (flannel does not do FQDN; the
#     real egress is Cilium/Hetzner, ADR-0014; declaring Egress here would
#     break builds/GitOps over an unreachable FQDN);
#  c) REAL DELIVERY — if the directory has a kustomization, netpol.yaml MUST
#     be in resources, or ArgoCD ignores it IN SILENCE (the trap that nearly
#     ate me: jenkins-secrets and argocd-secrets are kustomize).
D79=""
# It used to look at $ROOT/platform — the INSTANCE (the fourth case, along
# with 26, 90 and 91). The artifact is the seed.
ROOT="$P" python3 - <<'PY' 2>/tmp/vs79.err || D79="$(cat /tmp/vs79.err 2>/dev/null | tr '\n' ' ')"
import sys, os, yaml
ROOT = os.environ['ROOT']
targets = [
  ('k8s/base/trivy-system/netpol.yaml', 'trivy-system'),
  ('k8s/base/platform/jenkins-secrets/netpol.yaml', 'jenkins-system'),
  ('k8s/base/platform/argocd-secrets/netpol.yaml', 'argocd'),
]
spec = lambda d: d.get('spec', {})
errs = []
for rel, ns in targets:
    f = os.path.join(ROOT, rel)
    if not os.path.exists(f):
        errs.append("%s missing;" % rel); continue
    nps = [d for d in yaml.safe_load_all(open(f)) if d and d.get('kind') == 'NetworkPolicy']
    if not nps:
        errs.append("%s: no NetworkPolicy;" % rel); continue
    if {d['metadata'].get('namespace') for d in nps} != {ns}:
        errs.append("%s: namespace != %s;" % (rel, ns))
    if not any(spec(d).get('podSelector') == {} and 'Ingress' in spec(d).get('policyTypes', []) for d in nps):
        errs.append("%s: no default-deny ingress;" % rel)
    eg = [d['metadata']['name'] for d in nps if 'Egress' in spec(d).get('policyTypes', [])]
    if eg:
        errs.append("%s: declares Egress (iter2 is ingress-only): %s;" % (rel, eg))
    # delivery: if there is a kustomization in the dir, it MUST list netpol.yaml
    kf = os.path.join(os.path.dirname(f), 'kustomization.yaml')
    if os.path.exists(kf):
        k = yaml.safe_load(open(kf)) or {}
        if 'netpol.yaml' not in (k.get('resources') or []):
            errs.append("%s: the kustomization does not list netpol.yaml (ArgoCD would ignore it);" % rel)
    # trivy-system: init runs a trivy-probe INSIDE the ns (the
    # 'trivy-responde' gate, phase 80) → it MUST allow intra-ns ingress or
    # the default-deny cuts the probe with trivy Running (a regression caught
    # in the integration run of 2026-07-23).
    if ns == 'trivy-system':
        intra = any(
            'podSelector' in peer and 'namespaceSelector' not in peer
            for d in nps
            for rule in (spec(d).get('ingress') or [])
            for peer in (rule.get('from') or [])
        )
        if not intra:
            errs.append("%s: no intra-ns ingress (init's gate trivy-probe stays blocked);" % rel)
if errs:
    print(' '.join(errs), file=sys.stderr); sys.exit(1)
PY
# the 'trivy-responde' probe (phase 80) MUST retry INSIDE the pod: with trivy's
# default-deny, a freshly created pod loses the race against kube-router's
# ipset (exit 7) and the EXTERNAL retry does not help (a new pod every time).
# Without the internal loop, phase 80 stalls (run of 2026-07-23).
_T80="$PHASES/80-supply-chain.sh"
awk '/gate "trivy-responde"/{f=1} f{print} f&&/>\/dev\/null"/{exit}' "$_T80" 2>/dev/null \
    | grep -Eq "for i in |until curl" \
    || D79="$D79 the trivy-responde probe does not retry INSIDE the pod (it would lose the race with kube-router's netpol);"
if [[ -n "$D79" ]]; then fail "platform-netpol-iter2: $D79"
else pass "iter2: trivy/jenkins/argocd default-deny ingress-only, delivered by their App; the trivy probe tolerates the netpol race"; fi
}
