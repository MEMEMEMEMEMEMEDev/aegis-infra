# teeth of check 014b (no UI echo to stdout in the libs)
# The defect: the line break after `read -rsp` goes out through stdout
# and contaminates the value the function returns through $().
red_1() { printf '\n_ui_broken() { read -rsp "key: " x; echo\n}\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
control_1() { printf '\n_ui_healthy() { read -rsp "key: " x; echo >&2\n}\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
