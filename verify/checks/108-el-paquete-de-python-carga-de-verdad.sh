# titulo: el paquete de python no solo parsea: CARGA
# origen: nuevo en v3 — el renombrado ES->EN del 2026-08-24
check() {
# El check 001 valida SINTAXIS con `ast.parse`, y eso es exactamente lo
# que no alcanza. `from . import rutas` parsea perfecto el día que
# `rutas.py` pasa a llamarse `paths.py`: el archivo es válido, la
# referencia está muerta, y nadie se entera hasta que alguien corre el
# comando.
#
# Pasó acá el 2026-08-24, durante el renombrado al inglés: se movieron
# los tres módulos del paquete, `aegis verify` quedó TODO PASS con sus
# 113 checks, y `aegis org apply` reventaba en el import. Ciento trece
# checks y ninguno importaba el paquete que usan seis comandos.
#
# Es la misma familia que el 001 documenta —«filtro que deja de morder
# cuando el archivo cambia de forma»— corrida un escalón: acá el
# instrumento medía la forma correcta (el árbol sintáctico) de la
# pregunta equivocada. Parsear no es cargar.
#
# Se mide en DOS pasadas porque son dos fallos distintos y hay que
# poder decir cuál es:
#   (a) estático: todo `from aegis import X` / `import aegis.X` del
#       producto nombra un módulo que EXISTE en lib/aegis/;
#   (b) real: cada módulo del paquete se importa de verdad, que es lo
#       único que prueba que sus propios imports internos resuelven.
command -v python3 >/dev/null || { skip "no hay python3: no puedo cargar el paquete"; return; }
[[ -d "$LIBS/aegis" ]] || { skip "no existe $LIBS/aegis — no hay paquete que cargar"; return; }

D108="$(python3 - "$AEGIS_ROOT" <<'PY'
import ast, pathlib, subprocess, sys

root = pathlib.Path(sys.argv[1])
libs, libexec = root / "lib", root / "libexec"
pkg = libs / "aegis"

# Los módulos que el paquete OFRECE, derivados del directorio: una
# lista escrita a mano se desactualiza el día que alguien agrega uno.
disponibles = {p.stem for p in pkg.glob("*.py") if p.stem != "__init__"}
fallos = []

# (a) ESTÁTICO — todo import de `aegis` nombra algo que existe.
def fuentes():
    for base in (libs, libexec):
        for p in base.rglob("*"):
            if not p.is_file() or "__pycache__" in p.parts:
                continue
            if p.suffix == ".py":
                yield p
            elif p.suffix == "":
                try:
                    if p.open("rb").read(200).splitlines()[0].find(b"python") >= 0:
                        yield p
                except (OSError, IndexError):
                    pass

n_imports = 0
for p in fuentes():
    try:
        arbol = ast.parse(p.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError:
        continue                      # es del check 001, no de este
    for nodo in ast.walk(arbol):
        pedidos = []
        if isinstance(nodo, ast.ImportFrom):
            # `from aegis import a, b` y `from . import a, b` (dentro del paquete)
            if nodo.module == "aegis" or (nodo.level and nodo.module is None
                                          and pkg in p.parents):
                pedidos = [a.name for a in nodo.names]
            elif nodo.module and nodo.module.startswith("aegis."):
                pedidos = [nodo.module.split(".", 1)[1]]
            elif nodo.level and nodo.module and pkg in p.parents:
                pedidos = [nodo.module]
        elif isinstance(nodo, ast.Import):
            pedidos = [a.name.split(".", 1)[1] for a in nodo.names
                       if a.name.startswith("aegis.")]
        for m in pedidos:
            n_imports += 1
            if m not in disponibles:
                fallos.append(f"{p.relative_to(root)}:{nodo.lineno} importa "
                              f"'aegis.{m}' y lib/aegis/{m}.py no existe")

# (b) REAL — cada módulo se importa de verdad, en un intérprete limpio.
# Subproceso y no `importlib` acá: un import que falla a medias deja
# basura en sys.modules y el siguiente miente.
for m in sorted(disponibles):
    r = subprocess.run([sys.executable, "-c", f"import aegis.{m}"],
                       cwd=str(root), env={"PATH": "/usr/bin:/bin",
                                           "PYTHONPATH": str(libs),
                                           "AEGIS_ROOT": str(root)},
                       capture_output=True, text=True)
    if r.returncode != 0:
        ultima = (r.stderr.strip().splitlines() or ["(sin stderr)"])[-1]
        fallos.append(f"lib/aegis/{m}.py NO carga: {ultima}")

print(f"    {len(disponibles)} módulos · {n_imports} imports del paquete verificados",
      file=sys.stderr)
print("; ".join(fallos))
PY
)"
if [[ -n "$D108" ]]; then fail "el paquete de python no carga: $D108"
else pass "todo módulo de lib/aegis/ carga en un intérprete limpio y todo import del producto nombra uno que existe"; fi
}
