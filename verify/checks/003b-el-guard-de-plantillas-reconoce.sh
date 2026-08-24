# titulo: el guard de plantillas reconoce todo placeholder que la semilla usa
# origen: nuevo en v3 — el defecto del 2026-08-24
check() {
# `aegis app` rinde las plantillas de seed/templates/ y después
# revisa que no quede ningún __X__ suelto: una plantilla que pide algo
# que el comando no sabe derivar tiene que FRENAR ahí, no entregarle al
# operador el repo de su app con el literal adentro.
#
# Ese guard es un patrón, y un patrón que no reconoce lo que busca es
# peor que no tenerlo: da la sensación de estar cubierto. Hasta el
# 2026-08-24 era `__[A-Z]+__`, que no matchea NINGÚN placeholder con
# guion bajo — ni __ROOT_DOMAIN__ ni __GH_OWNER__ ni __PLATFORM_REPO__.
#
# Así que este check no lee el patrón: lo EJERCE contra el vocabulario
# de placeholders del artefacto ENTERO, no solo contra los que las
# plantillas usan hoy. La diferencia no es cosmética: hoy las
# plantillas usan __ORG__, __DOMINIO__ y __REPO__, las tres sin guion
# bajo, así que medido contra ellas el patrón roto pasaba por sano.
# Lo delató su propio diente. Lo que el guard tiene que reconocer es
# lo que una plantilla PUEDE pedir, y eso es el vocabulario del
# artefacto.
APP="$AEGIS_ROOT/libexec/aegis-app"
[[ -r "$APP" ]] || { skip "no puedo ejercer el guard: falta libexec/aegis-app"; return; }
[[ -d "$SEED" ]] || { skip "no puedo ejercer el guard: no hay semilla/"; return; }
CIEGOS="$(APP="$APP" VOCABULARIO="$SEED" python3 - <<'PY' 2>/dev/null
import ast, os, re, sys, pathlib

fuente = pathlib.Path(os.environ["APP"]).read_text(encoding="utf-8")
patron = None
for nodo in ast.parse(fuente).body:                 # solo nivel de módulo
    if (isinstance(nodo, ast.Assign)
            and any(getattr(t, "id", None) == "PLACEHOLDER" for t in nodo.targets)
            and isinstance(nodo.value, ast.Call)
            and isinstance(nodo.value.args[0], ast.Constant)):
        patron = nodo.value.args[0].value
if patron is None:
    sys.exit(2)                                     # no pude: no es rojo

usados = set()
for p in pathlib.Path(os.environ["VOCABULARIO"]).rglob("*"):
    if not p.is_file():
        continue
    try:
        usados |= set(re.findall(r"__[A-Z0-9_]+__", p.read_text(encoding="utf-8")))
    except (UnicodeDecodeError, OSError):
        continue

guard = re.compile(patron)
print(" ".join(sorted(x for x in usados if not guard.search(x))))
PY
)"
RC=$?
if [[ $RC -ne 0 ]]; then
    skip "no pude ejercer el guard de plantillas (libexec/aegis-app no declara PLACEHOLDER en el módulo, o falta python3)"
elif [[ -n "$CIEGOS" ]]; then
    fail "el guard de aegis-app NO reconoce placeholders que la semilla usa: $CIEGOS"
else
    pass "el guard de aegis-app reconoce todo el vocabulario de placeholders de la semilla"
fi
}
