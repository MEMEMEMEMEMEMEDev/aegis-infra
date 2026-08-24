# teeth for check 063 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'check_domain_on_cloudflare' "$AEGIS_ROOT/init/phases/00-preflight.sh" > "$AEGIS_ROOT/init/phases/00-preflight.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/00-preflight.sh.tooth" "$AEGIS_ROOT/init/phases/00-preflight.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/00-preflight.sh"; }
