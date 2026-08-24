# title: CRD/webhook dependencies: provider BEFORE consumer (A v1.1)
# origin: verify-static.sh (v2) ══ 73
check() {
# Finding A v1.1 (6th instance of the family): argocd-secrets synced
# FIRST and contained a Certificate — whose webhook is provided by
# cert-manager, synced AFTERWARDS. Deterministic from cold. This check
# reads the REAL argo_sync ORDER in phase 35 and demands that every App
# containing resources of a domain (cert-manager.io, traefik.io,
# kyverno.io) be synced AFTER its provider:
D73=""
if ! python3 - "$AEGIS_ROOT" <<'EOF'
import sys, pathlib, re, yaml
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# 1) real order of the syncs in phase 35 (non-comment lines):
order, seen = [], set()
for ln in (root/"init/phases/35-gitops.sh").read_text().splitlines():
    s = ln.strip()
    if s.startswith("#"): continue
    m = re.match(r'argo_sync\s+([a-z0-9-]+)', s)
    if m and m.group(1) not in seen:
        seen.add(m.group(1)); order.append(m.group(1))
pos = {a: i for i, a in enumerate(order)}
# 2) path of each App (one App = one manifests dir):
apps = {}
for f in (P/"k8s"/"argocd-apps").glob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        src = d["spec"].get("source") or {}
        srcs = d["spec"].get("sources") or ([src] if src else [])
        for s in srcs:
            if s.get("path"):
                apps[d["metadata"]["name"]] = s["path"]
# 3) provider of each API domain:
providers = {"cert-manager.io": "cert-manager",
             "traefik.io": "traefik",
             "kyverno.io": "kyverno"}
bad = []
for app, path in apps.items():
    if app not in pos: continue          # phase 35 does not sync it
    d = P/path
    if not d.is_dir(): continue
    for f in list(d.glob("*.yaml")) + list(d.glob("*.yml")):
        try: docs = [x for x in yaml.safe_load_all(f.open()) if x]
        except Exception: continue
        for doc in docs:
            api = str(doc.get("apiVersion", ""))
            dom = api.split("/")[0]
            prov = providers.get(dom)
            if not prov or prov == app: continue
            if prov not in pos:
                bad.append(f"{app} uses {dom} ({doc.get('kind')}) and its provider {prov} is NOT synced in phase 35")
            elif pos[prov] > pos[app]:
                bad.append(f"{app} (sync #{pos[app]}) contains {doc.get('kind')}/{dom} but its provider {prov} syncs AFTERWARDS (#{pos[prov]}) — INVERTED dependency")
if bad:
    for b in bad: print("  " + b, file=sys.stderr)
    sys.exit(1)
EOF
then D73="$D73 inverted CRD/webhook dependency (detail above);"
fi
# the generic helper exists and phase 35 uses it on cert-manager (the
# App being Healthy does NOT prove that the webhook is answering):
nc "$LIBS/common.sh" | grep -q '^webhook_serving()' \
    || D73="$D73 the webhook_serving helper is missing (endpoints, not Healthy);"
# the webhook-not-answering signature must cover the REAL text from the
# run and must NOT mask a broken manifest (proven live right here):
if ! bash -c "source <(grep '^AEGIS_WEBHOOK_NOTREADY_SIGS=' "$LIBS/common.sh")
      grep -qiE \"\$AEGIS_WEBHOOK_NOTREADY_SIGS\" <<< 'failed calling webhook \"webhook.cert-manager.io\": no endpoints available for service' \
      && ! grep -qiE \"\$AEGIS_WEBHOOK_NOTREADY_SIGS\" <<< 'manifest is invalid: missing required field'" 2>/dev/null; then
    D73="$D73 the webhook-not-answering signature does not cover the real error (or it masks a broken manifest);"
fi
ASY73="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY73" | grep -q 'wh_refires' \
    || D73="$D73 argo_sync without a LONG retry for a webhook that is not ready (3x10s was insufficient: 1-2 min from cold);"
echo "$ASY73" | grep -q 'syncResult.resources\[\]\?.message' \
    || D73="$D73 argo_sync classifies by the App's SYMPTOM and does not read the cause in the per-resource detail;"
NC35="$(nc "$PHASES/35-gitops.sh")"
echo "$NC35" | grep -q 'webhook_serving cert-manager' \
    || D73="$D73 phase 35 does not wait for the ENDPOINTS of cert-manager's webhook;"
L_CM="$(awk '!/^[[:space:]]*#/ && /argo_sync cert-manager /{print NR; exit}' "$PHASES/35-gitops.sh")"
L_WH="$(awk '!/^[[:space:]]*#/ && /webhook_serving cert-manager/{print NR; exit}' "$PHASES/35-gitops.sh")"
L_SEC="$(awk '!/^[[:space:]]*#/ && /argo_sync argocd-secrets/{print NR; exit}' "$PHASES/35-gitops.sh")"
L_SELF="$(awk '!/^[[:space:]]*#/ && /argo_sync argocd /{print NR; exit}' "$PHASES/35-gitops.sh")"
if [[ -z "$L_CM" || -z "$L_WH" || -z "$L_SEC" ]] || ! (( L_CM < L_WH && L_WH < L_SEC )); then
    D73="$D73 the order cert-manager → webhook serving → argocd-secrets is not respected;"
fi
# the OLD constraint is still alive (argocd-secrets before the self, or
# the \$github-webhook:token pointer stays literal — ADR-0015):
if [[ -z "$L_SELF" ]] || ! (( L_SEC < L_SELF )); then
    D73="$D73 argocd-secrets stopped going before argocd-self (ADR-0015);"
fi
# Finding C: the commands printed for copy-pasting have to work from
# ANY cwd — the operator copies them from another directory, and
# `./init/aegis-init.sh --from 50` does not exist there.
#
# In v2 the criterion was «make it absolute» and the line said
# `$INIT_DIR/aegis-init.sh`. In v3 the criterion is met better: the
# command is `aegis init`, which is on the PATH (phase 05 installs it as
# a symlink) and comes from $AEGIS_CMD, never a literal — the class rule
# against the ~155 strings of Class E. What this check forbids is the
# RELATIVE form, which is the one that failed.
RESUME="$(nc "$LIBEXEC/aegis-init" | grep 'Resume:' | head -1)"
if [[ -z "$RESUME" ]]; then
    D73="$D73 C: init no longer prints how to resume;"
elif ! grep -q 'AEGIS_CMD' <<< "$RESUME" && ! grep -qE 'Resume: (/|\$AEGIS_ROOT)' <<< "$RESUME"; then
    D73="$D73 C: the resume command cannot be pasted from another cwd ($RESUME);"
fi
if [[ -n "$D73" ]]; then fail "dependencies/UX:$D73"
else pass "providers before consumers (phase 35's real order verified), webhook by ENDPOINTS, absolute resume"; fi
}
