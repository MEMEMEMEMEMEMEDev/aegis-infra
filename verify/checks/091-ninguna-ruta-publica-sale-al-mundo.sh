# titulo: ninguna ruta pública sale al mundo sin protección: Access delante o los tres middlewares (#81/#90)
# origen: verify-static.sh (v2) ══ 91
check() {
# PARTIDO en v3: este archivo mide la DISYUNTIVA (Access o los tres
# middlewares). Que las copias a mano del canario sigan siendo byte a
# byte lo que emite el generador se mide en el 091b — eran dos
# preguntas distintas en un solo veredicto, y cuando la segunda perdió
# su sujeto (org-blog vive en la instancia, no en el artefacto) se
# llevaba puesta a la primera.
# Hasta el 2026-08-13 el cluster tenía CERO middlewares: los sitios
# públicos no mandaban una sola cabecera de seguridad, no había
# rate-limit y no había límite de tamaño de cuerpo.
#
# Este check cubre las DOS formas de que eso vuelva sin que nadie lo
# note, que son distintas:
#
#   a) una ruta nueva sin la lista de middlewares. La lista va POR
#      RUTA (traefik no tiene «middlewares de la IngressRoute»), así
#      que agregar un `publico:` y olvidarse deja esa ruta desnuda
#      mientras las otras del mismo archivo están protegidas.
#
#   b) el canario. Su ruteo es el ÚNICO escrito a mano —no tiene
#      contrato del que derivar, a propósito— así que sus tres
#      middlewares son una COPIA de los que emite el generador. Una
#      copia que nadie compara se desincroniza; ésta se compara.
#
#   c) las rutas de PLATAFORMA (k8s/base/** de la SEMILLA — B4,
#      fase-85 §5). La doctrina completa es una DISYUNTIVA: o el
#      hostname está detrás de Access (derivado de los .tf del
#      módulo, como el check 90 — jamás una lista horneada acá) o la
#      ruta lleva los tres middlewares. grafana cumple por Access y
#      va sin middlewares; ntfy no puede ir tras Access (la app del
#      teléfono no se autentica ante Cloudflare) y cumple por los
#      tres — que además entran a la comparación de (b), porque son
#      otra copia a mano de lo que emite el generador.
D91=""
python3 - "$P/k8s/organizations" "$P/k8s/base" \
    "$P/tofu/modules/cloudflare-access" <<'PY' || D91="$D91 (ver detalle arriba);"
import re, sys, pathlib, yaml

raiz = pathlib.Path(sys.argv[1])
if not raiz.is_dir():
    print(f"    no existe {raiz}", file=sys.stderr); sys.exit(1)

specs, malo = {}, []
for ruteo in sorted(raiz.glob("*/ruteo.yaml")):
    org = ruteo.parent.name
    docs = [d for d in yaml.safe_load_all(ruteo.read_text()) if d]
    mws = {d["metadata"]["name"]: d["spec"]
           for d in docs if d.get("kind") == "Middleware"}
    rutas = [r for d in docs if d.get("kind") == "IngressRoute"
             for r in d["spec"].get("routes", [])]

    # (a) toda ruta con los tres, y referenciando middlewares que
    #     EXISTEN en este mismo archivo. Una referencia a un nombre
    #     inexistente no es un error ruidoso en traefik: la ruta queda
    #     sin ese middleware y sigue sirviendo.
    for r in rutas:
        usa = [m["name"] for m in r.get("middlewares", []) or []]
        faltan = [s for s in ("cabeceras", "ritmo", "cuerpo")
                  if not any(u.endswith("-" + s) for u in usa)]
        if faltan:
            malo.append(f"{org}: la ruta {r['match'][:40]!r} no lleva {faltan}")
        for u in usa:
            if u not in mws:
                malo.append(f"{org}: la ruta referencia el middleware {u!r} que NO existe en su ruteo.yaml")

    # (b) el contenido, indexado por sufijo para poder comparar entre
    #     organizaciones (blog-ritmo vs canary-ritmo).
    for nombre, spec in mws.items():
        specs.setdefault(nombre.rsplit("-", 1)[-1], {})[org] = spec

# (c) plataforma: toda IngressRoute de k8s/base/** de la semilla, con
#     la disyuntiva Access-o-middlewares. La lista de hostnames tras
#     Access se DERIVA del módulo de la semilla (todos los .tf: HCL
#     fusiona el directorio, y grafana.tf es archivo propio).
base, modulo = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
tras_access = set()
for tf in sorted(modulo.glob("*.tf")):
    tras_access |= set(re.findall(
        r'^\s*domain\s*=\s*"([a-z0-9-]+)\.\$\{var\.root_domain\}',
        tf.read_text(), re.M))
if not tras_access:
    malo.append(f"el módulo de Access en {modulo} no declara ningún domain "
                "— sin esa lista la disyuntiva no se puede evaluar")
n_plat = 0
for f in sorted(base.rglob("*.yaml")):
    docs = [d for d in yaml.safe_load_all(f.read_text())
            if isinstance(d, dict)]
    if not any(d.get("kind") == "IngressRoute" for d in docs):
        continue
    rel = f.relative_to(base)
    mws = {d["metadata"]["name"]: d["spec"]
           for d in docs if d.get("kind") == "Middleware"}
    for d in docs:
        if d.get("kind") != "IngressRoute":
            continue
        for r in d["spec"].get("routes", []):
            n_plat += 1
            hosts = re.findall(r"Host\(`([a-z0-9-]+)\.", r.get("match", ""))
            if hosts and all(h in tras_access for h in hosts):
                continue        # la puerta la pone Cloudflare, no traefik
            usa = [m["name"] for m in r.get("middlewares", []) or []]
            faltan = [s for s in ("cabeceras", "ritmo", "cuerpo")
                      if not any(u.endswith("-" + s) for u in usa)]
            if faltan:
                malo.append(f"base/{rel}: la ruta {r.get('match', '')[:40]!r} "
                            f"no está tras Access ({'/'.join(sorted(tras_access))}) "
                            f"ni lleva {faltan}")
            for u in usa:
                if u not in mws:
                    malo.append(f"base/{rel}: la ruta referencia el middleware "
                                f"{u!r} que NO existe en su archivo")
    # sus copias de los tres middlewares entran a la comparación (b);
    # SOLO esos tres sufijos: un middleware de otra clase en base/ no
    # tiene referencia en el generador que exigirle.
    for nombre, spec in mws.items():
        pref, _, suf = nombre.rpartition("-")
        if suf in ("cabeceras", "ritmo", "cuerpo"):
            specs.setdefault(suf, {})[pref] = spec
print(f"    {n_plat} rutas de plataforma en {base.name}/ bajo la disyuntiva "
      f"Access({len(tras_access)} hostnames) o middlewares", file=sys.stderr)

for m in malo:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if malo else 0)
PY
if [[ -n "$D91" ]]; then fail "middlewares del borde:$D91"
else pass "toda ruta pública (organizaciones y plataforma) va tras Access o lleva cabeceras+ritmo+cuerpo"; fi
}
