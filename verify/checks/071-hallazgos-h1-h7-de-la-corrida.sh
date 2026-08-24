# title: hallazgos H1-H7 de la corrida #15 ABSORBIDOS (sesión 22)
# origen: verify-static.sh (v2) ══ 71
check() {
D71=""
# H7: la App kyverno-policies ignora el defaulting de Kyverno y el
# ignore se RESPETA en el apply (sin la syncOption, solo afecta el diff):
if ! python3 - "$P/k8s/argocd-apps/ci-supply-tenants.yaml" <<'EOF'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
app = next(d for d in docs if d.get("metadata", {}).get("name") == "kyverno-policies")
ign = app["spec"].get("ignoreDifferences") or []
assert any(i.get("kind") == "ClusterPolicy" and i.get("jqPathExpressions") for i in ign), "sin ignoreDifferences de ClusterPolicy"
exprs = [e for i in ign for e in i.get("jqPathExpressions", [])]
assert any("admission" in e for e in exprs), "falta .spec.admission"
assert any("verifyImages" in e and "required" in e for e in exprs), "faltan los defaults de verifyImages"
assert not any(".spec.background" == e.strip() for e in exprs), "ignora .spec.background (campo DECLARADO en git — su drift debe detectarse)"
opts = app["spec"]["syncPolicy"].get("syncOptions") or []
assert "RespectIgnoreDifferences=true" in opts, "sin RespectIgnoreDifferences=true"
EOF
then D71="$D71 H7: la App kyverno-policies no absorbe el defaulting (OutOfSync eterno garantizado en la 80);"
fi
# H5: argo_sync detecta el patch no-op y acepta el estado presente:
ASY71="$(body_of argo_sync "$LIBS/common.sh")"
# (el ancla es el GREP del output del patch — el string 'no change'
#  pelado también vive en el log_warn: mención≠uso, otra vez)
echo "$ASY71" | grep -q "grep -q 'no change'" \
    || D71="$D71 H5: argo_sync no detecta el patch no-op ('no change');"
echo "$ASY71" | grep -q 'YA existe' \
    || D71="$D71 H5: argo_sync no acepta el estado deseado ya-existente (la sobre-corrección del bug C sigue viva);"
# H5(ii): evidencia periódica en las esperas del helper y del gate:
(( "$(echo "$ASY71" | grep -c '% 30')" >= 2 )) \
    || D71="$D71 H5: esperas de argo_sync sin evidencia periódica (los 17 min mudos);"
echo "$ASY71" | grep -q 'kubectl -n argocd wait application' \
    && D71="$D71 H5: la espera de Healthy sigue siendo un kubectl wait MUDO;"
body_of argo_secrets_gate "$LIBS/common.sh" | grep -q 'esperando Synced' \
    || D71="$D71 H5: argo_secrets_gate con camino de espera mudo;"
# H7 bonus: timeout con op Succeeded dice DRIFT con los recursos:
nc "$LIBS/common.sh" | grep -q 'DRIFT' \
    || D71="$D71 H7: los timeouts de sync no distinguen drift de timing;"
# H6: la 12 siembra el canary SIEMPRE (historia huérfana + force) y
# el gate valida el sha remoto == seed (resultado, no intención):
NC12="$(nc "$PHASES/12-workrepos.sh")"
echo "$NC12" | grep -q 'app-repo-estado-igual-al-seed' \
    || D71="$D71 H6: la 12 sin gate de estado-igual-al-seed;"
grep -q 'ya tiene contenido — no re-siembro' "$PHASES/12-workrepos.sh" \
    && D71="$D71 H6: el skip 'no re-siembro' sigue vivo (deja .argocd-source residual);"
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/12-workrepos.sh" \
  | nc | grep 'SEED_TMP.*push' | grep -q -- '--force' \
    || D71="$D71 H6: el push del canary sin --force (la historia vieja sobrevive);"
# H6 defensa: la 70 valida el tag EFECTIVO del Deployment:
nc "$PHASES/70-deploy-auto.sh" | grep -q 'tag-efectivo-en-registry' \
    || D71="$D71 H6: la 70 no valida el tag efectivo contra el registry;"
# H4: existencia de coredns ANTES del rollout status, en el playbook
# (awk sobre líneas NO-comentario: el grep -n crudo ancló el
# COMENTARIO que documenta el fix — mención≠uso, dentro del propio
# check, tercera vez):
PB71="$P/ansible/playbooks/install-k3s.yml"
L_EX="$(awk '!/^[[:space:]]*#/ && /coredns EXISTA/{print NR; exit}' "$PB71")"
L_RS="$(awk '!/^[[:space:]]*#/ && /rollout status/{print NR; exit}' "$PB71")"
if [[ -z "$L_EX" || -z "$L_RS" ]] || (( L_EX > L_RS )); then
    D71="$D71 H4: el playbook corre rollout status sin esperar la EXISTENCIA de coredns;"
fi
nc "$LIBS/common.sh" | grep -q '(¿red?)' \
    && D71="$D71 H4: retry_net sigue etiquetando todo fallo como '(¿red?)';"
# H1: gate de skew real + la señal débil degradada:
nc "$PHASES/00-preflight.sh" | grep -q 'gate "reloj-sin-skew"' \
    || D71="$D71 H1: la 00 sin gate de skew de reloj;"
CSK71="$(body_of check_clock_skew "$LIBS/checks.sh")"
echo "$CSK71" | grep -qi 'date:' || D71="$D71 H1: el skew no se mide contra el header Date;"
echo "$CSK71" | grep -q '60' || D71="$D71 H1: sin umbral de 60s;"
nc "$PHASES/00-preflight.sh" | grep -q 'gate .*check_clock_ntp' \
    && D71="$D71 H1: timedatectl sigue siendo GATE (señal no confiable con chrony);"
# H3: jq auto-instalado con NOPASSWD antes del gate:
NC00="$(nc "$PHASES/00-preflight.sh")"
echo "$NC00" | grep -q 'install -y jq' \
    || D71="$D71 H3: la 00 no instala jq sola (freno determinista de toda VM limpia);"
# H2: runner con 2ª pasada + purga del estado generado:
nc "$LIBEXEC/aegis-verify" | grep -q 'AEGIS_VERIFY_RETRY=1' \
    || D71="$D71 H2: el runner no confirma los FAIL con una 2ª pasada;"
nc "$LIBEXEC/aegis-verify" | grep -q '__pycache__' \
    || D71="$D71 H2: no se purga el estado generado (__pycache__) antes de los checks;"
if [[ -n "$D71" ]]; then fail "hallazgos #15:$D71"
else pass "H1-H7 absorbidos: skew gateado, jq solo, existencia→estado en playbooks, no-op aceptado, seed=estado, defaulting ignorado"; fi
}
