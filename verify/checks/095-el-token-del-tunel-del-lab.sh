# titulo: el token del túnel del lab nunca se imprime
# origen: verify-static.sh (v2) ══ 95
check() {
# El token es un credencial de larga vida que da entrada de red al
# VPS. bin/aegis-vps lo mueve por VARIABLE y por STDIN: jamás argv
# (visible en /proc), jamás pantalla, jamás disco fuera de /dev/shm.
# Ya perdimos un token por pegarlo en un transcript (2026-08-19);
# esta clase de fuga no se re-audita a ojo: se verifica.
D95=""
VPS_BIN="$LIBEXEC/aegis-vps"
if [[ ! -f "$VPS_BIN" ]]; then D95="$D95 falta $VPS_BIN;"
else
    [[ -x "$VPS_BIN" ]] || D95="$D95 aegis-vps no es ejecutable;"
    grep -q 'output -raw tunnel_token' "$VPS_BIN" \
        || D95="$D95 no lee el token con output -raw (¿de dónde lo saca entonces?);"
    SUMIDEROS="$(grep -n 'tunnel_token' "$VPS_BIN" | grep -E 'echo |printf |[^"$(]cat ' || true)"
    [[ -z "$SUMIDEROS" ]] \
        || D95="$D95 una línea con tunnel_token tiene un sumidero de impresión: $SUMIDEROS;"
    grep -q 'cloudflared service install "\$(cat)"' "$VPS_BIN" \
        || D95="$D95 la entrega no usa \"\$(cat)\" (por stdin): el token estaría en argv del ssh remoto;"
    grep -qE 'install .*\$TOKEN|install .*\$\{TOKEN' "$VPS_BIN" \
        && D95="$D95 la entrega expande una variable en argv;"
    grep -q 'shred' "$VPS_BIN" \
        || D95="$D95 no hay shred: el render quedaría vivo en /dev/shm hasta el reboot;"
    # bug real (2026-08-23, primera entrega): el wrapper exige -chdir
    # RELATIVO (#46), así que hay que invocarlo parado en tofu/ — desde
    # otro cwd el env "no existe" y un token VACÍO viaja al VPS:
    grep -q 'cd "\$RAIZ/tofu" && "\$WRAPPER"' "$VPS_BIN" \
        || D95="$D95 el wrapper no se invoca desde \$RAIZ/tofu: con -chdir relativo el token sale vacío (pasó el 2026-08-23);"
fi
if [[ -n "$D95" ]]; then fail "95:$D95"
else pass "aegis-vps: el token viaja por variable y stdin, muere con shred"; fi
}
