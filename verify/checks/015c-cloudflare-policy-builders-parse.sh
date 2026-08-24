# title: D11 — the Cloudflare policy builders parse
# origin: verify-static.sh (v2) ══ 15, part c — split in v3
check() {
# With ast and not by importing them: an import leaves __pycache__
# inside the artifact, and the artifact is a pure function of the
# versioned tree.
D15C=""
for pb in cf-policy-tunnel.py cf-policy-dns.py cf-policy-access.py; do
    [[ -f "$LIBS/$pb" ]] || { D15C="$D15C $pb missing;"; continue; }
    python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$LIBS/$pb" 2>/dev/null \
        || D15C="$D15C $pb does not parse;"
done
if [[ -n "$D15C" ]]; then fail "CF policy builders:$D15C"
else pass "CF policy builders parse"; fi
}
