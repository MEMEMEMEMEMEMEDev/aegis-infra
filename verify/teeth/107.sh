# dientes del check 107 (el camino de error no puede reventar)
#
# El defecto que este check impide: el operador pide auxilio y en vez
# del motivo recibe un traceback sobre la línea que iba a dárselo.

# el defecto exacto que tenía `aegis dev seed` hasta el 2026-08-24
red_1() {
    python3 - "$AEGIS_ROOT/libexec/dev/seed" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
p.write_text(s.replace('morir(f"no existe {CONF}: sin los valores de esta "',
                       'morir(f"no existe {CONF.relative_to(RAIZ)}: sin los valores de esta "'), encoding="utf-8")
PY
}

# y en un raise, que es la otra forma de salir por la mala
red_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
i = s.index("\ndef ", s.index("\n"))
s = s[:i] + '\ndef _diente_107(x, raiz):\n    raise Error(f"{x.relative_to(raiz)} no sirve")\n' + s[i:]
p.write_text(s, encoding="utf-8")
PY
}

# control: un relative_to FUERA del camino de error es legítimo (así se
# muestran las rutas del producto) y no puede ponerlo rojo.
control_1() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
i = s.index("\ndef ", s.index("\n"))
s = s[:i] + '\ndef _diente_107(x, raiz):\n    return str(x.relative_to(raiz))\n' + s[i:]
p.write_text(s, encoding="utf-8")
PY
}
