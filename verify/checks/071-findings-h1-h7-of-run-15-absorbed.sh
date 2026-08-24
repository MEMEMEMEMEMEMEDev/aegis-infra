# title: findings H1-H7 of run #15 ABSORBED (session 22)
# origin: verify-static.sh (v2) ══ 71
check() {
D71=""
# H7: the kyverno-policies App ignores Kyverno's defaulting and the
# ignore is RESPECTED at apply time (without the syncOption it only
# affects the diff):
if ! python3 - "$P/k8s/argocd-apps/ci-supply-tenants.yaml" <<'EOF'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
app = next(d for d in docs if d.get("metadata", {}).get("name") == "kyverno-policies")
ign = app["spec"].get("ignoreDifferences") or []
assert any(i.get("kind") == "ClusterPolicy" and i.get("jqPathExpressions") for i in ign), "no ignoreDifferences for ClusterPolicy"
exprs = [e for i in ign for e in i.get("jqPathExpressions", [])]
assert any("admission" in e for e in exprs), ".spec.admission missing"
assert any("verifyImages" in e and "required" in e for e in exprs), "the verifyImages defaults are missing"
assert not any(".spec.background" == e.strip() for e in exprs), "it ignores .spec.background (a field DECLARED in git — its drift must be detectable)"
opts = app["spec"]["syncPolicy"].get("syncOptions") or []
assert "RespectIgnoreDifferences=true" in opts, "no RespectIgnoreDifferences=true"
EOF
then D71="$D71 H7: the kyverno-policies App does not absorb the defaulting (eternal OutOfSync guaranteed in phase 80);"
fi
# H5: argo_sync detects the no-op patch and accepts the present state:
ASY71="$(body_of argo_sync "$LIBS/common.sh")"
# (the anchor is the GREP of the patch's output — the bare 'no change'
#  string also lives in the log_warn: mention≠use, once again)
echo "$ASY71" | grep -q "grep -q 'no change'" \
    || D71="$D71 H5: argo_sync does not detect the no-op patch ('no change');"
echo "$ASY71" | grep -q 'ALREADY exists' \
    || D71="$D71 H5: argo_sync does not accept an already-existing desired state (bug C's over-correction is still alive);"
# H5(ii): periodic evidence in the helper's and the gate's waits:
(( "$(echo "$ASY71" | grep -c '% 30')" >= 2 )) \
    || D71="$D71 H5: argo_sync's waits without periodic evidence (the 17 mute minutes);"
echo "$ASY71" | grep -q 'kubectl -n argocd wait application' \
    && D71="$D71 H5: the Healthy wait is still a MUTE kubectl wait;"
body_of argo_secrets_gate "$LIBS/common.sh" | grep -q 'waiting for Synced' \
    || D71="$D71 H5: argo_secrets_gate with a mute waiting path;"
# H7 bonus: a timeout with the op Succeeded says DRIFT along with the resources:
nc "$LIBS/common.sh" | grep -q 'DRIFT' \
    || D71="$D71 H7: sync timeouts do not distinguish drift from timing;"
# H6: phase 12 ALWAYS seeds the canary (orphan history + force) and the
# gate validates that the remote sha == the seed (result, not intention):
NC12="$(nc "$PHASES/12-workrepos.sh")"
echo "$NC12" | grep -q 'app-repo-estado-igual-al-seed' \
    || D71="$D71 H6: phase 12 without a state-equals-the-seed gate;"
grep -q 'ya tiene contenido — no re-siembro' "$PHASES/12-workrepos.sh" \
    && D71="$D71 H6: the refuse-to-re-seed skip is still alive (it leaves a residual .argocd-source);"
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/12-workrepos.sh" \
  | nc | grep 'SEED_TMP.*push' | grep -q -- '--force' \
    || D71="$D71 H6: the canary's push without --force (the old history survives);"
# H6 defence: phase 70 validates the Deployment's EFFECTIVE tag:
nc "$PHASES/70-deploy-auto.sh" | grep -q 'tag-efectivo-en-registry' \
    || D71="$D71 H6: phase 70 does not validate the effective tag against the registry;"
# H4: coredns must EXIST before the rollout status, in the playbook
# (awk over NON-comment lines: the raw grep -n anchored on the COMMENT
# that documents the fix — mention≠use, inside the check itself, for the
# third time):
PB71="$P/ansible/playbooks/install-k3s.yml"
L_EX="$(awk '!/^[[:space:]]*#/ && /coredns EXISTA/{print NR; exit}' "$PB71")"
L_RS="$(awk '!/^[[:space:]]*#/ && /rollout status/{print NR; exit}' "$PB71")"
if [[ -z "$L_EX" || -z "$L_RS" ]] || (( L_EX > L_RS )); then
    D71="$D71 H4: the playbook runs rollout status without waiting for coredns to EXIST;"
fi
nc "$LIBS/common.sh" | grep -q '(¿red?)' \
    && D71="$D71 H4: retry_net still labels every failure as '(¿red?)';"
# H1: a real skew gate + the weak signal demoted:
nc "$PHASES/00-preflight.sh" | grep -q 'gate "reloj-sin-skew"' \
    || D71="$D71 H1: phase 00 without a clock-skew gate;"
CSK71="$(body_of check_clock_skew "$LIBS/checks.sh")"
echo "$CSK71" | grep -qi 'date:' || D71="$D71 H1: the skew is not measured against the Date header;"
echo "$CSK71" | grep -q '60' || D71="$D71 H1: no 60s threshold;"
nc "$PHASES/00-preflight.sh" | grep -q 'gate .*check_clock_ntp' \
    && D71="$D71 H1: timedatectl is still a GATE (an unreliable signal with chrony);"
# H3: jq auto-installed with NOPASSWD before the gate:
NC00="$(nc "$PHASES/00-preflight.sh")"
echo "$NC00" | grep -q 'install -y jq' \
    || D71="$D71 H3: phase 00 does not install jq by itself (a deterministic stop on every clean VM);"
# H2: runner with a 2nd pass + purge of the generated state:
nc "$LIBEXEC/aegis-verify" | grep -q 'AEGIS_VERIFY_RETRY=1' \
    || D71="$D71 H2: the runner does not confirm the FAILs with a 2nd pass;"
nc "$LIBEXEC/aegis-verify" | grep -q '__pycache__' \
    || D71="$D71 H2: the generated state (__pycache__) is not purged before the checks;"
if [[ -n "$D71" ]]; then fail "findings of #15:$D71"
else pass "H1-H7 absorbed: skew gated, jq on its own, existence→state in the playbooks, no-op accepted, seed=state, defaulting ignored"; fi
}
