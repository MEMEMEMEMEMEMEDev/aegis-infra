# title: toda credencial que el init GENERA se sabe rotar (#82)
# origen: verify-static.sh (v2) ══ 89
check() {
# La rotación fue prosa hasta el 2026-08-12: rotation-checklist.md tenía
# once ítems y aegis-rotate.sh mecanizaba UNO (invalidar el store). El
# resto lo ejecutaba una persona de memoria, incluido el paso que
# distingue "roté" de "roté y funciona".
#
# Al mecanizarlo aparece un riesgo nuevo y silencioso: agregar una
# credencial al init y NO agregarla a la tabla de recetas. Esa
# credencial existiría, se persistiría en el store, y el día que
# hubiera que rotarla nadie sabría cómo — sin un solo error, porque
# nada la nombra.
#
# Es el mismo principio que las tablas EXCLUSIONES/DELIBERADAS de
# aegis dev seed: una entrada que falta es un ERROR, no un detalle.
#
# NO se mide contra init/.state-secrets/ a propósito. Ese directorio es
# ESTADO de una instancia viva y puede no existir en un checkout limpio;
# un check atado a él daría verde por ausencia (C15: un check atado a un
# LUGAR miente apenas algo se mueve). Se mide contra el ARTEFACTO: lo
# que las fases declaran generar.
D89=""
python3 - "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" <<'PY' || D89="$D89 (ver detalle arriba);"
import pathlib, re, sys

init = pathlib.Path(sys.argv[1])
libexec = pathlib.Path(sys.argv[3])
# El rotador dejó de ser un script suelto del init: es un comando
# (libexec/aegis-rotate, `aegis rotate`). La receta que este check
# busca es la misma; cambió dónde vive.
rotar = libexec / "aegis-rotate"
if not rotar.is_file():
    print(f"    no existe {rotar}: nadie sabe rotar NADA"); sys.exit(1)

# 1. lo que el init declara generar y persistir, leyendo las fases.
#    Cuatro formas de NOMBRAR material del store, y hacen falta las
#    cuatro: los tokens de Cloudflare se persisten con el nombre en una
#    VARIABLE (mint_cf_token hace `persist_secret "$store"`), así que
#    sólo aparecen literales del lado de restore_secret. Detectado
#    porque este mismo check los reportó como recetas huérfanas.
PATRONES = [
    re.compile(r'\bgen_or_restore(?:_keypair)?\s+([a-z][a-z0-9_]*)'),
    re.compile(r'\bpersist_secret\s+([a-z][a-z0-9_]*)'),
    re.compile(r'\brestore_secret\s+([a-z][a-z0-9_]*)'),
    re.compile(r'STATE_SECRETS/([a-z][a-z0-9_]*)\.enc'),
]
# Y el punto ciego que queda: un persist_secret cuyo nombre viene por
# variable Y que nunca se restaura por literal sería invisible para
# este check. No se puede resolver leyendo texto, así que en vez de
# fingir cobertura total, el check NOMBRA lo que no puede ver.
INDIRECTO = re.compile(r'\bpersist_secret\s+"\$')

generadas, indirecciones = {}, []
for fase in sorted((init / "phases").glob("*.sh")):
    for i, linea in enumerate(fase.read_text().splitlines(), 1):
        if linea.lstrip().startswith("#"):
            continue          # los comentarios NOMBRAN helpers, no los llaman
        codigo = linea.split("#", 1)[0]
        for pat in PATRONES:
            for n in pat.findall(codigo):
                generadas.setdefault(n, f"{fase.name}:{i}")
        if INDIRECTO.search(codigo):
            indirecciones.append(f"{fase.name}:{i}")

if not generadas:
    print("    no se encontró NINGUNA credencial generada: el check no evaluó nada")
    sys.exit(1)

# 2. lo que la tabla de recetas cubre. Se lee la TABLA, no el archivo
#    entero: un nombre suelto en un comentario no es una receta.
texto = rotar.read_text()
tablas = re.findall(r"<<'TABLA'\n(.*?)\nTABLA", texto, re.S)
if not tablas:
    print("    aegis-rotate no tiene ninguna tabla RECETAS reconocible")
    sys.exit(1)
recetas = {}
for t in tablas:
    for linea in t.splitlines():
        if not linea.strip() or linea.lstrip().startswith("#"):
            continue
        campos = linea.split("|")
        if len(campos) < 7:
            print(f"    receta mal formada (se esperan 7 campos): {linea}")
            sys.exit(1)
        recetas[campos[0]] = campos[1]

CLASES = {"normal", "delegada", "irreducible", "prohibida", "tofu", "manual"}
malo = []

for n, donde in sorted(generadas.items()):
    if n not in recetas:
        malo.append(f"'{n}' se genera en {donde} y NO tiene receta en aegis-rotate: "
                    f"existe, se persiste, y nadie sabe rotarla")
    elif recetas[n] not in CLASES:
        malo.append(f"'{n}' tiene clase desconocida '{recetas[n]}' (válidas: {sorted(CLASES)})")

# 3. y al revés: una receta para algo que ya nadie genera es una nota
#    vieja, y una nota vieja deja de proteger sin avisar. Excepción
#    declarada: tunnel_token lo produce tofu (fase 25), no el store.
# Material que vive en el store pero que el init NO produce hoy. Cada
# entrada es una DEUDA declarada, no una excepción cómoda: lo correcto
# es que una fase la genere. Si esta lista crece sin tarea asociada, el
# init y la instancia se están separando.
NO_LAS_GENERA_EL_INIT = {
    "tunnel_token":            "la produce tofu en la fase 25",
    "argocd_admin_pass":       "deuda #86: debería producirla la fase 30",
    "argocd_server_secretkey": "deuda #86: debería producirla la fase 30",
    "cf_access_token":         "deuda #88: la fase 15 no sabe acuñarlo todavía",
    "access_st_id":            "lo crea tofu junto con las apps de Access (#76)",
    "access_st_secret":        "lo crea tofu junto con las apps de Access (#76)",
}
for n, clase in sorted(recetas.items()):
    if n not in generadas and n not in NO_LAS_GENERA_EL_INIT:
        malo.append(f"la receta de '{n}' no corresponde a ninguna credencial que el "
                    f"init genere hoy: o se dejó de generar, o la nota quedó vieja")

for m in malo:
    print(f"    {m}")
if not malo:
    print(f"    {len(generadas)} credenciales generadas, todas con receta "
          f"({sorted(generadas)})", file=sys.stderr)
    if indirecciones:
        # Verde CON su punto ciego a la vista: estas líneas persisten con
        # el nombre en una variable. Hoy las cubre el literal del
        # restore_secret; si mañana alguien agrega una que no se
        # restaure por literal, este check NO la va a ver.
        print(f"    (punto ciego declarado: persist_secret con nombre en variable en "
              f"{', '.join(indirecciones)} — cubiertas hoy por su restore_secret literal)",
              file=sys.stderr)
sys.exit(1 if malo else 0)
PY
if [[ -n "$D89" ]]; then fail "recetas de rotación:$D89"
else pass "toda credencial que el init genera tiene receta de rotación declarada, y no sobra ninguna"; fi
}
