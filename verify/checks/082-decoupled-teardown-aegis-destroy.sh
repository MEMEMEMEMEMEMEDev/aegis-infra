# title: decoupled teardown: aegis-destroy (end of the dirty cloud) (W-10/R5)
# origin: verify-static.sh (v2) ══ 82
check() {
# CF cleanup was COUPLED to the creation path (phase 25 only deletes if you
# recreate). aegis-destroy decouples it. Invariants:
D82=""
DS="$LIBEXEC/aegis-destroy"
if [[ -f "$DS" ]]; then
    bash -n "$DS" 2>/dev/null || D82="$D82 aegis-destroy.sh does not parse;"
    [[ -x "$DS" ]] || D82="$D82 aegis-destroy.sh not executable;"
    # A14: destroy THROUGH THE WRAPPER (raw tofu → phantom destroys)
    grep -q 'tofu-apply.sh' "$DS" || D82="$D82 does not use the tofu wrapper (A14);"
    grep -Eq '"\$TOFU".*destroy' "$DS" || D82="$D82 does not destroy CF through the wrapper;"
    # dry-run by default (destroy is irreversible); it only acts with --yes
    grep -q 'YES=0'   "$DS" || D82="$D82 not dry-run by default (dangerous);"
    grep -q -- '--yes' "$DS" || D82="$D82 no --yes gate;"
    # it loads the config (without it, it does not know what to destroy)
    # The instance's config is called aegis.conf and lives in $AEGIS_HOME
    # (02 §1): destroy reads it from there, not from the product's directory.
    grep -q 'AEGIS_CONF\|aegis.conf' "$DS" || D82="$D82 does not load init's config;"
else
    D82="$D82 init/aegis-destroy.sh missing;"
fi
if [[ -n "$D82" ]]; then fail "teardown:$D82"
else pass "aegis-destroy: CF through the wrapper, dry-run+--yes, config loaded (dirty cloud decoupled)"; fi
}
