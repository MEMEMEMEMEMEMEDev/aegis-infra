# teeth of check 015a (D11: no secrets manager assumed)
red_1() { printf '\nlog_info "save this in Bitwarden before continuing"\n' >> "$AEGIS_ROOT/init/phases/10-age-ceremony.sh"; }
# control: the check excludes the verify/ DIRECTORY, not a file name —
# if it went back to excluding by name, this would turn it red.
control_1() { printf '\n# title: mention of Bitwarden in a check\ncheck() { pass "nothing"; }\n' > "$AEGIS_ROOT/verify/checks/998-legitimate-mention.sh"; }
