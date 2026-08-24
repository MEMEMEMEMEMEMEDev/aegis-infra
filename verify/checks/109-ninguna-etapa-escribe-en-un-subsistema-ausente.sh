# title: ninguna etapa del generador escribe donde el artefacto no tiene carpeta
# origen: nuevo en v3 — reproducido el 2026-08-24 sobre la semilla pelada
check() {
# El bug, con reproducción: un contrato válido SIN bloque `ai:` hacía
# morir a `aegis org apply` con
#
#     FileNotFoundError: .../k8s/base/ai-system/routes.yaml
#
# y no al principio — DESPUÉS de escribir los seis manifiestos de la
# organización. Árbol a medias, traceback, y la culpa pareciendo del
# contrato.
#
# La causa no fue el AI: fue que una etapa del generador daba por
# sentado un directorio que el artefacto puede no traer. Con la
# decisión de que el subsistema de AI no viaja en la semilla, «no
# está» dejó de ser una anomalía y pasó a ser la forma normal de un
# árbol recién clonado — y el mismo agujero espera a cualquier
# subsistema que se saque después.
#
# Por eso el check mide la CLASE y no el caso: para cada etapa
# `aplicar_*` se resuelve a qué archivo escribe, se pregunta si ese
# directorio existe en la SEMILLA, y si no existe se exige una de dos
# —crearlo con `os.makedirs`, o preguntar y salir con motivo antes de
# escribir. Lo que no se acepta es escribir a ciegas.
[[ -f "$LIBS/aegis/org.py" ]] || { skip "no existe lib/aegis/org.py"; return; }
[[ -d "$SEED/platform" ]] || { skip "no existe seed/platform: sin artefacto contra el cual medir"; return; }

D109="$(python3 - "$LIBS/aegis/org.py" "$SEED/platform" <<'PY'
import ast, os, sys

fuente, semilla = sys.argv[1], sys.argv[2]
arbol = ast.parse(open(fuente, encoding="utf-8").read())

# Las constantes de ruta, resueltas desde su asignación: os.path.join(
# RAIZ, "k8s", "base", …) -> ("k8s", "base", …). RAIZ es la instancia,
# así que las partes que siguen son la ruta relativa dentro del árbol.
constantes = {}
for n in arbol.body:
    if not (isinstance(n, ast.Assign) and len(n.targets) == 1
            and isinstance(n.targets[0], ast.Name)):
        continue
    v = n.value
    if not (isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute)
            and v.func.attr == "join"):
        continue
    partes = [a.value for a in v.args[1:] if isinstance(a, ast.Constant)]
    if len(partes) == len(v.args) - 1 and partes:
        constantes[n.targets[0].id] = partes

def escrituras(fn):
    """(nodo, nombre_constante) de cada open(CONST, 'w') de la función."""
    for n in ast.walk(fn):
        if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                and n.func.id == "open" and len(n.args) >= 2):
            continue
        modo = n.args[1]
        if not (isinstance(modo, ast.Constant) and "w" in str(modo.value)):
            continue
        if isinstance(n.args[0], ast.Name) and n.args[0].id in constantes:
            yield n, n.args[0].id

# Qué cuenta como PREGUNTAR por el directorio. La primera versión de
# este check aceptaba «cualquier return temprano», y su propio diente
# la denunció: `if viejo == nuevo: return 0` ya estaba en todas las
# etapas, así que la guarda parecía existir sin existir. Un check que
# se conforma con la forma en vez del sentido no protege nada.
PREGUNTAS = {"isdir", "exists", "is_dir", "makedirs"}

def pregunta_por_el_arbol(nodo):
    """¿Este nodo consulta si algo existe en el sistema de archivos?"""
    return any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
               and n.func.attr in PREGUNTAS for n in ast.walk(nodo))

# Las guardas pueden estar a un nivel de indirección: la etapa llama a
# un helper y el helper es quien mira el disco. Se derivan del módulo,
# no se listan a mano.
helpers = {f.name for f in arbol.body
           if isinstance(f, ast.FunctionDef) and pregunta_por_el_arbol(f)}

fallos, n_etapas, n_guardadas = [], 0, 0
for fn in arbol.body:
    if not (isinstance(fn, ast.FunctionDef) and fn.name.startswith("aplicar_")):
        continue
    n_etapas += 1
    for nodo, const in escrituras(fn):
        rel = os.path.join(*constantes[const][:-1]) if len(constantes[const]) > 1 else ""
        if not rel or os.path.isdir(os.path.join(semilla, rel)):
            continue                       # el artefacto SÍ trae la carpeta
        # La etapa tiene que, ANTES de escribir: mirar el disco ella
        # misma, o llamar a alguien que lo mire y poder volverse por
        # ahí (un `return` que dependa de esa llamada).
        guardada = False
        for n in fn.body:
            if n.lineno >= nodo.lineno:
                break
            if pregunta_por_el_arbol(n):
                guardada = True
                break
            llama_helper = any(isinstance(c, ast.Call) and isinstance(c.func, ast.Name)
                               and c.func.id in helpers for c in ast.walk(n))
            if llama_helper:
                guardada = True
                break
        if guardada:
            n_guardadas += 1
        else:
            fallos.append(f"{fn.name}() escribe {const} en '{rel}/', que la "
                          f"semilla NO trae, sin crear el directorio ni "
                          f"preguntar antes (línea {nodo.lineno})")

print(f"    {n_etapas} etapas · {n_guardadas} escrituras a subsistema ausente, "
      f"todas con guarda o makedirs", file=sys.stderr)
print("; ".join(fallos))
PY
)"
if [[ -n "$D109" ]]; then fail "el generador escribe a ciegas: $D109"
else pass "toda etapa que escribe en un directorio que la semilla no trae, o lo crea o pregunta y sale con motivo"; fi
}
