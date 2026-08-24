# titulo: archivos que las fases referencian EXISTEN (clase bug 4)
# origen: verify-static.sh (v2) ══ 17
check() {
# el requirements.txt de ansible estaba referenciado y NO existía —
# la fase 20 murió en la VM. Misma clase que el check 5 (paths de
# Apps): toda referencia estática de las fases a archivos del
# artefacto se verifica acá (ansible/* relativo a platform/ — la
# fase 20 hace cd — y las rutas $AEGIS_V2_ROOT/init/*):
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"semilla"/"plataforma"
ok = True; n = 0
for ph in sorted((root/"init"/"phases").glob("*.sh")):
    t = ph.read_text()
    for m in re.finditer(r'\bansible/[A-Za-z0-9_./-]+\.(?:yml|yaml|txt|ini|j2)\b', t):
        n += 1
        if not (P/m.group(0)).is_file():
            print(f"FAIL {ph.name}: referencia inexistente platform/{m.group(0)}")
            ok = False
    for m in re.finditer(r'\$AEGIS_V2_ROOT/(init/[A-Za-z0-9_./-]+\.(?:py|sh|tpl))\b', t):
        n += 1
        if not (root/m.group(1)).is_file():
            print(f"FAIL {ph.name}: referencia inexistente {m.group(1)}")
            ok = False
print(f"referencias estáticas de fases verificadas: {n}")
sys.exit(0 if ok else 1)
EOF
then pass "toda referencia estática de las fases existe"
else fail "fase referencia archivo inexistente"; fi
}
