# titulo: D11 — los policy builders de Cloudflare parsean
# origen: verify-static.sh (v2) ══ 15, parte c — partida en v3
check() {
# Con ast y no importándolos: un import deja __pycache__ dentro del
# artefacto, y el artefacto es función pura del árbol versionado.
D15C=""
for pb in cf-policy-tunnel.py cf-policy-dns.py cf-policy-access.py; do
    [[ -f "$LIBS/$pb" ]] || { D15C="$D15C falta $pb;"; continue; }
    python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$LIBS/$pb" 2>/dev/null \
        || D15C="$D15C $pb no parsea;"
done
if [[ -n "$D15C" ]]; then fail "builders de policies CF:$D15C"
else pass "builders de policies CF parsean"; fi
}
