# teeth of check 009 ('|| true' only where it is legitimate)
# NEGATIVE: the check demands ABSENCE, so the tooth ADDS the defect.
red_1() { printf '\ntrue || true   # swallowing a real error\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
control_1() { printf '\n# a comment that mentions || true without using it\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
