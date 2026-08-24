# teeth for check 085 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'chmod\s+6?00\s+"?\$HOME/\.kube/config|install -m\s*600' "$AEGIS_ROOT/init/phases/20-k3s.sh" > "$AEGIS_ROOT/init/phases/20-k3s.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/20-k3s.sh.tooth" "$AEGIS_ROOT/init/phases/20-k3s.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
