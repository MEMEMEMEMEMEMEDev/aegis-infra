# titulo: NetworkPolicies de plataforma iter2: ingress-only + entrega real (W-07)
# origen: verify-static.sh (v2) ══ 79
check() {
# iter2 aísla el PLANO DE CONTROL (trivy/jenkins/argocd) por ingress. NO
# incluye registry/kyverno/cert-manager/infra-edge: van en iter3 con corrida
# propia (pull cluster-wide y admisión = 🔴🔴; el doc 04-netpol-diseno.md §3
# los pone al final). Invariantes que este check clava:
#  a) los 3 netpols existen, con default-deny INGRESS;
#  b) INGRESS-ONLY — ningún netpol declara Egress (flannel no hace FQDN; el
#     egress real es Cilium/Hetzner, ADR-0014; declarar Egress acá rompería
#     builds/GitOps por FQDN inalcanzable);
#  c) ENTREGA REAL — si el directorio tiene kustomization, netpol.yaml DEBE
#     estar en resources, o ArgoCD lo ignora EN SILENCIO (el trap que casi
#     me come: jenkins-secrets y argocd-secrets son kustomize).
D79=""
# Miraba $ROOT/platform — la INSTANCIA (cuarto caso, con 26, 90 y 91).
# El artefacto es la semilla.
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
        errs.append("falta %s;" % rel); continue
    nps = [d for d in yaml.safe_load_all(open(f)) if d and d.get('kind') == 'NetworkPolicy']
    if not nps:
        errs.append("%s: sin NetworkPolicy;" % rel); continue
    if {d['metadata'].get('namespace') for d in nps} != {ns}:
        errs.append("%s: namespace != %s;" % (rel, ns))
    if not any(spec(d).get('podSelector') == {} and 'Ingress' in spec(d).get('policyTypes', []) for d in nps):
        errs.append("%s: sin default-deny ingress;" % rel)
    eg = [d['metadata']['name'] for d in nps if 'Egress' in spec(d).get('policyTypes', [])]
    if eg:
        errs.append("%s: declara Egress (iter2 es ingress-only): %s;" % (rel, eg))
    # entrega: si hay kustomization en el dir, DEBE listar netpol.yaml
    kf = os.path.join(os.path.dirname(f), 'kustomization.yaml')
    if os.path.exists(kf):
        k = yaml.safe_load(open(kf)) or {}
        if 'netpol.yaml' not in (k.get('resources') or []):
            errs.append("%s: kustomization no lista netpol.yaml (ArgoCD lo ignoraría);" % rel)
    # trivy-system: el init corre un trivy-probe DENTRO del ns (gate
    # 'trivy-responde', fase 80) → DEBE permitir ingress intra-ns o el
    # default-deny corta la probe con trivy Running (regresión cazada en
    # la corrida de integración 2026-07-23).
    if ns == 'trivy-system':
        intra = any(
            'podSelector' in peer and 'namespaceSelector' not in peer
            for d in nps
            for rule in (spec(d).get('ingress') or [])
            for peer in (rule.get('from') or [])
        )
        if not intra:
            errs.append("%s: sin ingress intra-ns (el trivy-probe del gate del init queda bloqueado);" % rel)
if errs:
    print(' '.join(errs), file=sys.stderr); sys.exit(1)
PY
# el probe 'trivy-responde' (fase 80) DEBE reintentar DENTRO del pod: con la
# default-deny de trivy, un pod recién creado pierde la carrera contra el
# ipset de kube-router (exit 7) y el retry EXTERNO no ayuda (pod nuevo cada
# vez). Sin el loop interno, la fase 80 frena (corrida 2026-07-23).
_T80="$FASES/80-supply-chain.sh"
awk '/gate "trivy-responde"/{f=1} f{print} f&&/>\/dev\/null"/{exit}' "$_T80" 2>/dev/null \
    | grep -Eq "for i in |until curl" \
    || D79="$D79 el probe trivy-responde no reintenta DENTRO del pod (perdería el race del netpol de kube-router);"
if [[ -n "$D79" ]]; then fail "netpol-plataforma-iter2: $D79"
else pass "iter2: trivy/jenkins/argocd default-deny ingress-only, entregados por su App; probe trivy tolera el race del netpol"; fi
}
