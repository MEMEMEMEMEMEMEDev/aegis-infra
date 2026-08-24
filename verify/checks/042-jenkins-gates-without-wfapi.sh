# title: Jenkins gates WITHOUT /wfapi/ (H3 #13 — plugin not installed)
# origin: verify-static.sh (v2) ══ 42
check() {
# /wfapi/ is provided by pipeline-stage-view (NOT installed; the
# stage-STEP and stage-tags-metadata ones are OTHER plugins) → an
# eternal 404 with the system working fine. The gates go through the
# core (/api/json) and the build console:
BAD42="$(grep -rn '/wfapi/' "$PHASES" "$AEGIS_ROOT/init/lib" \
    | nc_hits || true)"
AL_BODY="$(body_of _antiloop_skipped "$PHASES/70-deploy-auto.sh" \
    | nc)"
D42=""
[[ -n "$BAD42" ]] && D42="$D42 use of /wfapi/:"$'\n'"$BAD42"
echo "$AL_BODY" | grep -q '/api/json' \
    && echo "$AL_BODY" | grep -q 'skipped due to when conditional' \
    || D42="$D42 _antiloop_skipped does not validate through core+console;"
if [[ -n "$D42" ]]; then fail "wfapi:$D42"
else pass "zero /wfapi/; anti-loop validated through /api/json + console (core endpoint)"; fi

# HERE WAS check 43: the Image Updater's CR against the real schema of
# the CRD, with dry-run=server. It went away with the component in #59.
#
# The LESSON that motivated it is not lost and is worth more than the
# check: the original CR was written against an IMAGINARY schema
# —fields that existed nowhere in the CRD— and ArgoCD retried the apply
# forever with the error hidden inside operationState. That is where
# the SOURCE-IS-BINARY rule came from: a manifest is validated against
# the LIVE schema, not against what one believes it accepts. It still
# applies to any CR added tomorrow.
}
