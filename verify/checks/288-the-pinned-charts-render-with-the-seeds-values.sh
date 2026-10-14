# title: the pinned charts render with the seed's values, and the keys that matter reach the render (--with-charts)
# origin: verify-static.sh (v2) ══ 13 — until 2026-10-14 it lived inside check 074 behind `[[ "$1" == --with-charts ]]`, and check() receives no arguments: the branch never ran, and had it run it would have emitted one verdict per chart (review of 2026-10-13, 4B-1)
check() {
# WHAT THIS MEASURES, and why it is the one check that talks to the
# network. A values file with a key in the wrong place renders cleanly
# and does nothing: the chart ignores it and nobody is told. Three times
# that was a real bug: ArgoCD's `configs.cm` literal-with-a-dot (the
# key was there, the render did not carry it), traefik 40.x ignoring
# `service.type` on the old path (run #5, finding B: an eternal
# LoadBalancer <pending>), and the trustedIPs of A31 not reaching the
# args. So this does not ask «does the values file parse»: it renders
# every adopted chart, at its pinned version, with the seed's values,
# and asks whether the EFFECT is in the output.
#
# It costs a fetch of every chart, so it runs only under --with-charts:
# the verifier exports AEGIS_VERIFY_WITH_CHARTS, and without it this is
# the third outcome, said out loud. The same when helm is not here. A
# network flake is a red of THIS check and not of the artifact; the
# CI workflow says why it does not run it.
D288="" N288=0
[[ "${AEGIS_VERIFY_WITH_CHARTS:-false}" == true ]] \
    || { skip "the pinned charts are rendered only under --with-charts (it fetches every chart from its repository)"; return; }
command -v helm >/dev/null 2>&1 \
    || { skip "helm is not installed here: the pinned charts cannot be rendered"; return; }

TMP288="$(mktemp -d)"; trap 'rm -rf "$TMP288"' EXIT
# the chart sources, read from the Applications and not from a list
# kept here: a chart adopted tomorrow is rendered tomorrow
python3 - "$AEGIS_ROOT" > "$TMP288/charts.tsv" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
for f in sorted((P/"k8s"/"argocd-apps").glob("*.yaml")):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        srcs = d["spec"].get("sources") or []
        for s in srcs:
            if "chart" in s:
                vf = (s.get("helm") or {}).get("valueFiles", [""])[0]
                vf = vf[len("$values/"):] if vf.startswith("$values/") else ""
                print(f'{d["metadata"]["name"]}\t{s["repoURL"]}\t{s["chart"]}\t{s["targetRevision"]}\t{vf}')
EOF
[[ -s "$TMP288/charts.tsv" ]] || { fail "no Application under seed/platform/k8s/argocd-apps declares a chart source: re-aim this check"; return; }

while IFS=$'\t' read -r app repo chart ver vf; do
    N288=$((N288+1))
    VAL288=()
    if [[ -n "$vf" && -f "$P/$vf" ]]; then
        # the seed's placeholders are substituted with dummies, for the
        # render only (the seed is not touched): a domain, an owner, a
        # retention that parses as one
        python3 - "$P/$vf" "$TMP288/$app-values.yaml" <<'EOF'
import re, sys
known = {"__ROOT_DOMAIN__": "example.com", "__ACME_EMAIL__": "a@example.com",
         "__REGISTRY_CLUSTER_IP__": "10.43.0.99", "__AEGIS_PROFILE__": "cloudflare",
         "__OBS_RETENCION_METRICAS__": "30d", "__OBS_RETENCION_LOGS__": "30d",
         "__AEGIS_CA_PEM__": "-----BEGIN CERTIFICATE-----"}
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"__[A-Z0-9_]+__", lambda m: known.get(m.group(0), "dummy-" + m.group(0).strip("_").lower().replace("_", "-")), text)
open(sys.argv[2], "w", encoding="utf-8").write(text)
EOF
        VAL288=(-f "$TMP288/$app-values.yaml")
    fi
    # OCI repos (schemeless, the way ArgoCD declares them — validated
    # live in v1 with quay.io/jetstack/charts): helm needs oci://<repo>/<chart>
    if [[ "$repo" == http* ]]; then REF288=("$chart" --repo "$repo")
    else REF288=("oci://$repo/$chart"); fi
    if ! helm template "$app" "${REF288[@]}" --version "$ver" "${VAL288[@]}" \
            --namespace dummy-ns >"$TMP288/$app.render" 2>"$TMP288/$app.err"; then
        D288="$D288 $app ($chart@$ver) does not render: $(tail -1 "$TMP288/$app.err" | cut -c1-160);"
        continue
    fi
    # an EFFECT, not «it did not break»: the VALUES must appear in the
    # render, as the ConfigMap carries them. The first tooth of this
    # check found two ways to ask this wrong: `grep -q server.insecure`
    # is a regex and also matches the misspelt `server-insecure`, and
    # the bare key appears in the Deployment's valueFrom whatever the
    # values say — only `server.insecure: "true"` is the effect.
    case "$app" in
        argocd)
            for must in 'kustomize.buildOptions: --enable-alpha-plugins' 'ksops' 'server.insecure: "true"'; do
                grep -qF -- "$must" "$TMP288/$app.render" \
                    || D288="$D288 the argocd render carries no '$must' (a key on a path the chart ignores?);"
            done ;;
        traefik)
            grep -qF 'type: ClusterIP' "$TMP288/$app.render" && ! grep -qF 'type: LoadBalancer' "$TMP288/$app.render" \
                || D288="$D288 the traefik render's Service is not ClusterIP (run #5 finding B: an eternal LoadBalancer <pending>);"
            grep -qF 'forwardedHeaders.trustedIPs=10.42' "$TMP288/$app.render" \
                || D288="$D288 the traefik render carries no trustedIPs in its args (A31 not applied);"
            ;;
    esac
done < "$TMP288/charts.tsv"

printf '    %s chart(s) fetched at their pinned version and rendered with the seed'"'"'s values\n' "$N288"
if [[ -n "$D288" ]]; then fail "the pinned charts do not render as the seed intends:$D288"
else pass "every adopted chart renders at its pinned version with the seed's values, and the argocd and traefik renders carry the keys three real bugs lost ($N288 charts)"; fi
}
