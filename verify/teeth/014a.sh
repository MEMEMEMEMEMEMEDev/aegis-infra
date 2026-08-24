# teeth of check 014a (log_* to stderr)
# The real defect of validation #1: a log that goes back to stdout
# contaminates every function captured with $().
red_1() { sed -i 's|^log_info()  { printf .*|log_info()  { printf "[INFO] %s\\n" "$*"; }|' "$AEGIS_ROOT/lib/common.sh"; }
control_1() { printf '\n# legitimate comment about log_info\n' >> "$AEGIS_ROOT/lib/common.sh"; }
