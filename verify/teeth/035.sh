# teeth of check 035 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE '_jenkins_quota_stall "\$every"' "$AEGIS_ROOT/lib/jenkins.sh" > "$AEGIS_ROOT/lib/jenkins.sh.tooth" \
        && mv "$AEGIS_ROOT/lib/jenkins.sh.tooth" "$AEGIS_ROOT/lib/jenkins.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/lib/jenkins.sh"; }
