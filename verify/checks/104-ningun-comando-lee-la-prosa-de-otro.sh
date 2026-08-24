# titulo: ningún comando decide leyendo la PROSA de otro
# origen: V-104 (03 §3) — nuevo en v3
check() {
# A3 del registro, con línea: aegis-app:713 decidía si el webhook se
# había creado buscando el texto «webhook creado» en la salida de
# aegis-webhook. Un cambio de redacción —una tilde, una mayúscula, un
# «ya estaba» en vez de «creado»— rompía el programa sin tocar una
# línea de lógica, y el síntoma aparecía en OTRO comando.
#
# El estado entre comandos viaja por CONTRATO: líneas
# `aegis: <paso> <estado>` y --json. La prosa es para las personas.
#
# Se mide con el AST y no con grep, a propósito: la primera versión de
# este check usaba una expresión regular y mordió su propia
# documentación —el docstring de cli.py que CITA el bug para
# explicarlo—. Mención ≠ uso: es la clase que ya se pagó en los checks
# 22, 25, 66 y 71, y no hay razón para pagarla una quinta vez.
D104=""
ROOT="$AEGIS_ROOT" LIBEXEC="$LIBEXEC" LIBS="$LIBS" python3 - <<'PY' || D104=" (ver detalle arriba);"
import ast, os, pathlib, sys

# ALCANCE: la prosa de OTRO COMANDO DE AEGIS. Leer el texto de error de
# una herramienta ajena (gh, kubectl) es distinto: no controlamos su
# contrato y a veces no hay otra forma —aegis-app distingue un 404 de
# un 409 de GitHub así, y eso se queda—. Lo que esta regla prohíbe es
# que DOS COMANDOS DE LA CASA se hablen por prosa, porque ahí sí
# tenemos la alternativa y el bug ya pasó.
def aegis_en(nodo):
    """¿Esta llamada ejecuta un comando de aegis?"""
    for h in ast.walk(nodo):
        if isinstance(h, ast.Constant) and isinstance(h.value, str) and "aegis-" in h.value:
            return True
        if isinstance(h, ast.Name) and h.id in AEGIS_VARS:
            return True
        if isinstance(h, ast.Attribute) and h.attr in ("run", "run_json") and \
           isinstance(h.value, ast.Name) and h.value.id == "cli":
            return False       # cli.run_json ES el contrato, no la prosa
    return False

malo = []
archivos = list(pathlib.Path(os.environ["LIBEXEC"]).glob("aegis-*"))
archivos += list(pathlib.Path(os.environ["LIBS"]).rglob("*.py"))
for f in archivos:
    if not f.is_file():
        continue
    txt = f.read_text(errors="replace")
    if "python" not in txt.split("\n")[0] and f.suffix != ".py":
        continue
    try:
        arbol = ast.parse(txt)
    except SyntaxError:
        continue
    # variables que apuntan a un comando de aegis (WEBHOOK = .../aegis-webhook)
    AEGIS_VARS = set()
    for n in ast.walk(arbol):
        if isinstance(n, ast.Assign):
            for h in ast.walk(n.value):
                if isinstance(h, ast.Constant) and isinstance(h.value, str) and "aegis-" in h.value:
                    for d in n.targets:
                        # nombres de una letra no son constantes de comando:
                        # son variables de paso (p = ArgumentParser(prog="aegis-app"))
                        if isinstance(d, ast.Name) and len(d.id) > 2:
                            AEGIS_VARS.add(d.id)
    # POR FUNCIÓN, no por archivo: `r` es el nombre más común del mundo
    # para el resultado de un subprocess, y mezclándolo todo el check
    # acusaba a `r = _gh(...)` de ser una llamada a aegis solo porque
    # OTRA función del mismo archivo tenía `r = subprocess.run([WEBHOOK]`.
    # Un check que grita por cosas sanas se deja de leer.
    # ast.walk() del módulo entero DESCIENDE a las funciones, con lo
    # cual «el ámbito módulo» volvía a mezclar todo y el arreglo no
    # arreglaba nada. El nivel superior se arma con su cuerpo, sin las
    # funciones.
    nivel_top = ast.Module(body=[n for n in arbol.body
                                 if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef,
                                                       ast.ClassDef))],
                           type_ignores=[])
    ambitos = [n for n in ast.walk(arbol)
               if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))] + [nivel_top]
    for amb in ambitos:
        SUCIAS = set()
        for n in ast.walk(amb):
            if isinstance(n, ast.Assign) and isinstance(n.value, ast.Call) and aegis_en(n.value):
                for d in n.targets:
                    if isinstance(d, ast.Name):
                        SUCIAS.add(d.id)
        if not SUCIAS:
            continue
        for n in ast.walk(amb):
            if isinstance(n, ast.Compare) and len(n.ops) == 1 and isinstance(n.ops[0], ast.In):
                izq, der = n.left, n.comparators[0]
                if not (isinstance(izq, ast.Constant) and isinstance(izq.value, str)):
                    continue
                base = None
                if isinstance(der, ast.Attribute) and der.attr in ("stdout", "stderr"):
                    base = der.value.id if isinstance(der.value, ast.Name) else None
                elif isinstance(der, ast.Name) and der.id in ("salida", "out"):
                    base = der.id
                if base and base in SUCIAS:
                    malo.append(f"    {f.name}:{n.lineno}: decide con «{izq.value}» "
                                f"dentro de la salida de otro comando de aegis")
for m in malo:
    print(m, file=sys.stderr)
sys.exit(1 if malo else 0)
PY
# y el equivalente en bash: capturar a otro comando y grepear la captura
for f in "$LIBEXEC"/aegis-*; do
    [[ -f "$f" ]] && head -1 "$f" | grep -q bash || continue
    nc "$f" | grep -qE '\$\((aegis_exec|[^)]*libexec/aegis-)[^)]*\)[^|]*\| *grep' \
        && D104="$D104 $(basename "$f") grepea la salida de otro comando;"
done
if [[ -n "$D104" ]]; then fail "estado por prosa:$D104"
else pass "ningún comando decide por el texto de otro: el estado viaja por contrato (aegis: <paso> <estado> / --json)"; fi
}
