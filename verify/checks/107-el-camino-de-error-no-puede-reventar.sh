# titulo: el camino de error no puede reventar
# origen: nuevo en v3 — el defecto del 2026-08-24
check() {
# Un comando que no puede seguir tiene UNA obligación: decir por qué.
# Si la expresión que arma ese mensaje puede levantar una excepción, el
# operador no recibe el motivo: recibe un traceback sobre otra cosa, y
# el «no pude» se disfraza de bug.
#
# `Path.relative_to` es la trampa concreta de este árbol porque levanta
# ValueError cuando la ruta no cuelga de la otra — y desde que el
# producto dejó de ser la instancia, ninguna ruta de la instancia
# cuelga del producto. Fue exactamente así: `aegis dev seed diff`
# contra una instancia de afuera moría con un traceback en la línea
# que iba a explicar que faltaba el conf.
#
# La regla es angosta a propósito: no dice «el mensaje tiene que ser
# lindo», dice que la construcción del mensaje no puede fallar.
CULPABLES="$(python3 - "$AEGIS_ROOT" <<'PY' 2>/dev/null
import ast, pathlib, sys

raiz = pathlib.Path(sys.argv[1])
ERRORES = {"morir", "die", "Error"}
malos = []

def nombre(f):
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        return f.attr
    return None

for p in sorted(list((raiz / "libexec").rglob("*")) + list((raiz / "lib").rglob("*.py"))):
    if not p.is_file():
        continue
    try:
        texto = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if not (p.suffix == ".py" or texto.startswith("#!") and "python" in texto.split("\n", 1)[0]):
        continue
    try:
        arbol = ast.parse(texto)
    except SyntaxError:
        continue                      # el check 1 se encarga de eso
    for nodo in ast.walk(arbol):
        args = None
        if isinstance(nodo, ast.Call) and nombre(nodo.func) in ERRORES:
            args = nodo.args + [k.value for k in nodo.keywords]
        elif isinstance(nodo, ast.Raise) and nodo.exc is not None:
            args = [nodo.exc]
        if not args:
            continue
        for a in args:
            for sub in ast.walk(a):
                if (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
                        and sub.func.attr == "relative_to"):
                    malos.append(f"{p.relative_to(raiz)}:{nodo.lineno}")

print(" ".join(sorted(set(malos))))
PY
)"
RC=$?
if [[ $RC -ne 0 ]]; then
    skip "no pude leer el árbol de python (falta python3 o no parsea)"
elif [[ -n "$CULPABLES" ]]; then
    fail "el mensaje de error se arma con algo que puede reventar (relative_to): $CULPABLES"
else
    pass "ningún camino de error arma su mensaje con una operación que pueda levantar excepción"
fi
}
