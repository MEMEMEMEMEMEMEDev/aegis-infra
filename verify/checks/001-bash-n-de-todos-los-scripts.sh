# titulo: bash -n de todos los scripts
# origen: verify-static.sh (v2) ══ 1
check() {
n=0
while IFS= read -r f; do
    if bash -n "$f" 2>/tmp/bashn.err; then n=$((n+1)); else
        fail "sintaxis: $f"; cat /tmp/bashn.err; fi
done < <(find "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" "$P" -name '*.sh' -type f)
pass "bash -n: $n scripts OK"
}
