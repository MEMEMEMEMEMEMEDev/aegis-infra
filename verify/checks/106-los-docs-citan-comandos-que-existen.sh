# title: todo comando citado en los documentos existe
# origen: V-106 (03 §8) — nuevo en v3
check() {
# H3 del registro: `organizacion.md:342` documentaba `aegis org rotar`,
# que no existe. El operador lo teclea, no pasa nada, y la conclusión
# natural es «me equivoqué yo» — no «el documento está viejo».
#
# Los documentos que el operador EJECUTA son código con otra sintaxis
# (Clase G). Si no se verifican, envejecen igual que el código pero sin
# que nada se ponga rojo.
#
# ALCANCE: solo lo que está entre comillas invertidas o en un bloque de
# código. La prosa dice «aegis se encarga de…» y eso no es una
# invocación. Y se saltean docs/cli/ y plan/, que son el REGISTRO de la
# decisión: ahí la tabla vieja→nueva tiene que poder nombrar lo viejo.
D106=""
ROOT="$AEGIS_ROOT" python3 - <<'PY' || D106=" (ver detalle arriba);"
import os, pathlib, re, sys

raiz = pathlib.Path(os.environ["ROOT"])
libexec = raiz / "libexec"
comandos = {f.name[len("aegis-"):] for f in libexec.glob("aegis-*") if f.is_file()}
# los subcomandos que cada comando declara (los que lo hacen)
subs = {}
for f in libexec.glob("aegis-*"):
    if not f.is_file():
        continue
    cab = "\n".join(f.read_text(errors="replace").split("\n")[:40])
    m = re.search(r'^# aegis-subcommands:[ \t]*(.*)$', cab, re.M)
    if m and m.group(1).strip():
        subs[f.name[len("aegis-"):]] = set(m.group(1).split())

# Los documentos de REGISTRO quedan fuera: plan/ y docs/cli/ llevan la
# tabla vieja→nueva (reescribir la columna vieja la destruiría), y
# ENCARGO.md es el mandato — describe lo que se PIDIÓ, incluido lo que
# todavía no existe (`aegis domain set` es tarea de T-04). Un documento
# que declara una intención no es un documento que se teclea.
REGISTRO = ("plan/", "docs/cli/", "ENCARGO.md", "Problema-")
docs = [p for p in raiz.rglob("*.md")
        if not any(r in str(p.relative_to(raiz)) for r in REGISTRO)
        and ".git" not in str(p)]
malo, n = [], 0
for d in docs:
    t = d.read_text(errors="replace")
    # en línea (`aegis x y`) y en bloque (``` ... ```)
    trozos = re.findall(r'`([^`\n]+)`', t)
    for bloque in re.findall(r'```[a-z]*\n(.*?)```', t, re.S):
        trozos += bloque.split("\n")
    for tr in trozos:
        m = re.match(r'^\s*(?:\$\s*)?aegis\s+([a-z][a-z-]*)(?:\s+([a-z][a-z-]*))?', tr)
        if not m:
            continue
        n += 1
        cmd, sub = m.group(1), m.group(2)
        if cmd not in comandos:
            malo.append(f"    {d.relative_to(raiz)}: «aegis {cmd}» no existe")
        elif sub and cmd in subs and sub not in subs[cmd] and not sub.startswith("-"):
            malo.append(f"    {d.relative_to(raiz)}: «aegis {cmd} {sub}» — {cmd} no declara ese subcomando")
print(f"    {n} invocaciones citadas en {len(docs)} documentos", file=sys.stderr)
for m_ in sorted(set(malo)):
    print(m_, file=sys.stderr)
sys.exit(1 if malo else 0)
PY
if [[ -n "$D106" ]]; then fail "documentos que citan comandos inexistentes:$D106"
else pass "todo comando citado en los documentos existe (la prosa no cuenta: solo código y comillas invertidas)"; fi
}
