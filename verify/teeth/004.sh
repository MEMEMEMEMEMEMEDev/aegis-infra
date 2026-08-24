# teeth of check 004 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# the subject disappears: if the check does not notice, it was not
# reading it
red_1() { rm -f "$AEGIS_ROOT/init/phases/85-observability.sh"; }

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/85-observability.sh"; }

# The tooth of the SECOND CATEGORY of producer, which until 2026-08-24
# did not exist because the category was dead: the check looked for the
# generator INSIDE the seed, where in v3 it can no longer be (the code
# lives in the product, 02 §1). With that branch dead, every secret
# derived from contracts came out «with no producer» — and one that
# really had no producer would have been lost in that noise.
#
# This red takes the generator out of where the check now looks for it.
# If the check went back to the old shape —«it is not there, so it does
# not apply»— it would pass green. That is what cannot happen again.
red_3() {
    mv "$AEGIS_ROOT/lib/aegis/org.py" "$AEGIS_ROOT/lib/aegis/org.py.hidden"
}

# control: documenting an existing entry better is the most legitimate
# change there is over a generator, and it cannot turn red.
#
# (The first version of this control ADDED a repeated entry and the
#  check bit it, rightly: a duplicate entry kills kustomize with
#  «already registered id». The tooth was wrong, not the check.)
control_2() {
    sed -i 's|^  - secret-garage-credentials\.enc\.yaml$|  # rotating it with the cluster up leaves the node unable to talk to itself\n  - secret-garage-credentials.enc.yaml|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/garage-system/secret-generator.yaml"
}
