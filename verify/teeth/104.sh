# dientes del check 104 (ningún comando lee la prosa de otro)
# A3: aegis-app decidía si el webhook se había creado buscando la
# frase «webhook creado» en la salida del otro comando.
rojo_1() {
    cat >> "$AEGIS_ROOT/libexec/aegis-app" <<'PY'


def _regresion_a3():
    import subprocess
    r = subprocess.run(["aegis-webhook", "--aplicar"], capture_output=True, text=True)
    return "webhook creado" in r.stdout
PY
}
