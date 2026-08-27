# teeth for check 140 (the docs cite alerts that exist)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# A protocol that says «when alert `X` fires, do Y» about an alert
# nobody wrote is an operator waiting for a page that never comes.
red_1() { printf '\nWhen alert `NoSuchAlert` fires, re-mirror the image.\n' >> "$AEGIS_ROOT/docs/OPERATE.md"; }
# control: a backticked name that is not an alert is not a citation
control_1() { printf '\nThe kind `ClusterPolicy` is what Kyverno reads.\n' >> "$AEGIS_ROOT/docs/OPERATE.md"; }
