# teeth for check 071 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'app-repo-estado-igual-al-seed' "$AEGIS_ROOT/init/phases/12-workrepos.sh" > "$AEGIS_ROOT/init/phases/12-workrepos.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/12-workrepos.sh.tooth" "$AEGIS_ROOT/init/phases/12-workrepos.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/12-workrepos.sh"; }
