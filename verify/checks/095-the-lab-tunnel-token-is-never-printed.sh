# title: the lab tunnel's token is never printed
# origin: verify-static.sh (v2) ══ 95
check() {
# The token is a long-lived credential that grants network entry to the
# VPS. bin/aegis-vps moves it through a VARIABLE and through STDIN:
# never argv (visible in /proc), never the screen, never disk outside
# /dev/shm. We already lost a token by pasting it into a transcript
# (2026-08-19); this class of leak is not re-audited by eye: it is
# verified.
D95=""
VPS_BIN="$LIBEXEC/aegis-vps"
if [[ ! -f "$VPS_BIN" ]]; then D95="$D95 $VPS_BIN missing;"
else
    [[ -x "$VPS_BIN" ]] || D95="$D95 aegis-vps is not executable;"
    grep -q 'output -raw tunnel_token' "$VPS_BIN" \
        || D95="$D95 it does not read the token with output -raw (where does it get it from, then?);"
    SINKS="$(grep -n 'tunnel_token' "$VPS_BIN" | grep -E 'echo |printf |[^"$(]cat ' || true)"
    [[ -z "$SINKS" ]] \
        || D95="$D95 a line with tunnel_token has a printing sink: $SINKS;"
    grep -q 'cloudflared service install "\$(cat)"' "$VPS_BIN" \
        || D95="$D95 the delivery does not use \"\$(cat)\" (through stdin): the token would be in the remote ssh's argv;"
    grep -qE 'install .*\$TOKEN|install .*\$\{TOKEN' "$VPS_BIN" \
        && D95="$D95 the delivery expands a variable into argv;"
    grep -q 'shred' "$VPS_BIN" \
        || D95="$D95 there is no shred: the render would stay alive in /dev/shm until the reboot;"
    # a real bug (2026-08-23, first delivery): the wrapper demands a
    # RELATIVE -chdir (#46), so it has to be invoked while standing in
    # tofu/ — from another cwd the env "does not exist" and an EMPTY
    # token travels to the VPS:
    grep -q 'cd "\$ROOT/tofu" && "\$WRAPPER"' "$VPS_BIN" \
        || D95="$D95 the wrapper is not invoked from \$ROOT/tofu: with a relative -chdir the token comes out empty (it happened on 2026-08-23);"
fi
if [[ -n "$D95" ]]; then fail "95:$D95"
else pass "aegis-vps: the token travels through a variable and stdin, and dies with shred"; fi
}
