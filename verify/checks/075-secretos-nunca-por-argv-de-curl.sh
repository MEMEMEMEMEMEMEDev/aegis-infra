# title: secretos NUNCA por argv de curl + bordes (W-03 / SEC-12/SEC-02)
# origen: verify-static.sh (v2) ══ 75
check() {
D75=""
# barrido de CLASE: ningún curl de las fases lleva el secreto en un -H
# de argv (visible en /proc/PID/cmdline). El header con secreto va por
# -K (config en tmpfs 600), como el netrc-por-archivo de jenkins.sh:
ARGV75="$(for f in "$AEGIS_ROOT"/init/phases/*.sh; do
    sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$f" | nc \
      | grep -E -- '-H +"[^"]*(Bearer|X-Auth-Key)[^"]*\$\(cat' \
      | sed "s|^|$(basename "$f"): |"
done)"
[[ -z "$ARGV75" ]] || D75="$D75 curl con secreto en -H de argv: $ARGV75;"
grep -q -- '-K "\$cfg"' "$PHASES/15-terceros.sh" \
    || D75="$D75 _cf_call no usa -K (config de curl por archivo);"
grep -q -- '-K "\$_cf_cfg"' "$PHASES/25-edge-tofu.sh" \
    || D75="$D75 _cf no usa -K (config de curl por archivo);"
grep -q "trap 'secrets_cleanup; exit 130' INT TERM" "$LIBS/secrets.sh" \
    || D75="$D75 secrets_cleanup no se dispara en INT/TERM (Ctrl-C dejaba material en tmpfs);"
grep -q 'chmod 600 "\$f"' "$PHASES/25-edge-tofu.sh" \
    || D75="$D75 el tfstate del túnel no se protege a 600 (token en claro 0664);"
if [[ -n "$D75" ]]; then fail "bordes:$D75"
else pass "secretos CF por -K (no argv), shred en INT/TERM, tfstate a 600"; fi
}
