# title: regcreds con type dockerconfigjson (corrida #9)
# origen: verify-static.sh (v2) ══ 28
check() {
# el kubelet IGNORA un Secret Opaque como imagePullSecret ("no basic
# auth credentials") — TODO make_enc_secret de un regcred debe llevar
# --type kubernetes.io/dockerconfigjson. Estático: en la fase 40, cada
# invocación con .dockerconfigjson= debe llevar el --type:
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
ok = True; n = 0
for ph in (root/"init"/"phases").glob("*.sh"):
    # normalizar continuaciones de línea (\<newline> → espacio) para
    # ver cada invocación completa en una línea (el regex multilinea
    # anterior no las capturaba — el teeth lo reveló):
    text = ph.read_text().replace("\\\n", " ")
    for m in re.finditer(r'make_enc_secret[^\n]*', text):
        call = m.group(0)
        if ".dockerconfigjson=" in call:
            n += 1
            if "--type kubernetes.io/dockerconfigjson" not in call:
                print(f"FAIL {ph.name}: regcred SIN --type dockerconfigjson (kubelet lo ignora como pull secret)")
                ok = False
print(f"invocaciones regcred verificadas: {n}")
sys.exit(0 if ok and n > 0 else 1)
EOF
then pass "todo regcred se cifra con type dockerconfigjson"
else fail "regcred sin type dockerconfigjson (bug fase 60 corrida #9)"; fi
}
