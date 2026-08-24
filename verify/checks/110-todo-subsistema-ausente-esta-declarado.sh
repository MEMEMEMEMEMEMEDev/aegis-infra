# titulo: todo subsistema que la semilla NO trae tiene su protocolo escrito
# origen: nuevo en v3 — P-03 (2026-08-24): AI viaja documentada, no cableada
check() {
# Un subsistema ausente POR DECISIÓN y uno ausente POR OLVIDO se ven
# exactamente igual desde afuera: una carpeta que no está. Esa es la
# forma canónica del renglón que falta, y es lo único que hace peligrosa
# la decisión de entregar aegis sin AI.
#
# La regla, entonces: si el producto sabe escribir en un directorio que
# el artefacto no trae, tiene que existir un documento que diga cómo se
# trae. No un comentario suelto — un protocolo, en docs/protocols/, que
# NOMBRE la ruta. Quien saque el próximo subsistema paga el mismo peaje.
#
# La lista de directorios NO se escribe acá: se DERIVA del generador,
# que es quien sabe dónde escribe. Una lista a mano se desactualiza el
# día que alguien agrega una etapa, y falla del lado que no avisa.
[[ -f "$LIBS/aegis/org.py" ]] || { skip "no existe lib/aegis/org.py: no puedo derivar los destinos"; return; }
[[ -d "$SEED/platform" ]] || { skip "no existe seed/platform"; return; }

D110="$(python3 - "$LIBS/aegis/org.py" "$SEED/platform" <<'PY'
import ast, os, re, sys

fuente, semilla = sys.argv[1], sys.argv[2]
arbol = ast.parse(open(fuente, encoding="utf-8").read())

# Los destinos que el generador conoce, sacados de sus constantes:
# os.path.join(RAIZ, "k8s", "base", "ai-system", "x.yaml") -> k8s/base/ai-system
destinos = set()
for n in arbol.body:
    if not (isinstance(n, ast.Assign) and len(n.targets) == 1
            and isinstance(n.targets[0], ast.Name)):
        continue
    v = n.value
    if not (isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute)
            and v.func.attr == "join"):
        continue
    partes = [a.value for a in v.args[1:] if isinstance(a, ast.Constant)]
    if len(partes) != len(v.args) - 1 or len(partes) < 2:
        continue
    # si la última parte parece archivo, el destino es su carpeta
    rel = os.path.join(*(partes[:-1] if "." in partes[-1] else partes))
    if rel:
        destinos.add(rel)

# Las DECLARACIONES de ausencia deliberada. No alcanza con que algún
# documento mencione la ruta de pasada —la primera versión de este
# check se conformaba con eso, y su propio diente la denunció: borrar
# el protocolo entero lo dejaba verde porque OTRO documento nombraba
# la carpeta al pasar. Hace falta una declaración explícita:
#
#     <!-- aegis-absent: k8s/base/ai-system -->
#
# y tiene que vivir en el documento que explica cómo se trae de vuelta.
protocolos = os.path.join(semilla, "docs", "protocols")
declarado = {}          # ruta -> archivo que la declara
if os.path.isdir(protocolos):
    for raiz, _, archivos in os.walk(protocolos):
        for a in sorted(archivos):
            if not a.endswith(".md"):
                continue
            ruta = os.path.join(raiz, a)
            for m in re.finditer(r"aegis-absent:\s*([^\s>]+)",
                                 open(ruta, encoding="utf-8",
                                      errors="replace").read()):
                declarado[m.group(1).rstrip("/")] = os.path.relpath(ruta, semilla)

fallos, n_ausentes = [], 0
for rel in sorted(destinos):
    if os.path.isdir(os.path.join(semilla, rel)):
        continue
    n_ausentes += 1
    if rel not in declarado:
        fallos.append(f"la semilla no trae '{rel}/' y ningún documento lo "
                      f"declara con `aegis-absent: {rel}`: un subsistema "
                      f"ausente sin declarar es indistinguible de un olvido")

# Y al revés, con el mismo rasero que la política de exclusión de
# `aegis dev seed`: una declaración que nombra algo PRESENTE es una
# mentira envejecida, y una mentira en el lugar donde se busca la
# verdad es peor que no tener nada escrito.
for rel, donde in sorted(declarado.items()):
    if os.path.isdir(os.path.join(semilla, rel)):
        fallos.append(f"{donde} declara ausente '{rel}/' y la semilla SÍ lo "
                      f"trae: la declaración envejeció y ahora miente")

print(f"    {len(destinos)} destinos del generador · {n_ausentes} ausentes · "
      f"{len(declarado)} declaraciones", file=sys.stderr)
print("; ".join(fallos))
PY
)"
if [[ -n "$D110" ]]; then fail "subsistema ausente sin declarar: $D110"
else pass "todo destino del generador que la semilla no trae tiene un protocolo que lo nombra"; fi
}
