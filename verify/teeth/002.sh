# teeth of check 002 (the YAML parse)
#
# What has to break is the PARSING, not the existence: deleting a file
# leaves the check counting one less and staying green.
#
# Note on method: the first red I tried —a list with ragged indentation—
# turned out to be VALID YAML. The tooth did not bite and the culprit
# was the tooth. That is why the runner runs them: a tooth that is
# written and never executed is exactly the promise without proof that
# this mechanism exists to prevent.

# an open flow: [one, two  with the bracket never closed
red_1() {
    printf '\nbroken_key: [one, two\n' >> "$AEGIS_ROOT/seed/platform/edge.yaml"
}

# an alias to an anchor that does not exist, in the SECOND document: it
# proves in passing that the check uses safe_load_all and not safe_load
# (the k8s manifests are multi-doc and with safe_load only the first
# would be read — the rest would enter the cluster with nobody looking
# at them).
# (The previous red was a duplicate key: PyYAML accepts it and
# overwrites the value. Another tooth that did not bite because of the
# tooth.)
red_2() {
    printf '\n---\nreference: *anchor_that_does_not_exist\n' >> "$AEGIS_ROOT/seed/platform/services.yaml"
}

# control: a comment in a YAML is still valid YAML
control_1() { printf '\n# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/edge.yaml"; }
