# teeth of check 016 (encrypting sops always with --config or --age)
# Without an explicit --age, sops takes the key from a .sops.yaml that
# may not be the one you think — and the file ends up encrypted for
# somebody else.
red_1() { printf '\nsops -e /tmp/something.yaml > /tmp/something.enc.yaml\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
control_1() { printf '\nsops -e --age "$AGE_PUBLIC" /tmp/something.yaml > /tmp/something.enc.yaml\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
