# titulo: todo seed con Service declara su EXPOSICIÓN (generalización CR-5)
# origen: verify-static.sh (v2) ══ 55
check() {
# CR-5 era detectable estáticamente: una app con Service y sin
# IngressRoute nace invisible desde el edge. Nadie la ve fallar: el
# manifiesto está perfecto y el tráfico no llega.
#
# La regla original era "IngressRoute EN EL MISMO ÁRBOL", y con #54 dejó
# de valer: la ruta se mudó al lado de la plataforma justamente para que
# el repo de la app no pueda escribirla. Buscarla donde ya no puede
# estar convertiría el arreglo en un rojo.
#
# El invariante no cambió — "algo rutea hacia ese Service" —, cambió
# dónde vive ese algo. Se busca por NOMBRE DE SERVICE en TODA la
# semilla: el árbol de la app y k8s/organizations/*/routes.yaml. Lo que
# importa es que exista una ruta, no quién la escribe.
if python3 - "$AEGIS_ROOT" <<'EOF'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); ok = True

def docs(f):
    try:
        for d in yaml.safe_load_all(f.open()):
            if d and isinstance(d, dict):
                yield d
    except Exception:
        return

# Todos los Services a los que apunta ALGUNA IngressRoute de la semilla,
# esté en el repo de la app o del lado de la plataforma.
ruteados = set()
for f in (root/"seed").rglob("*.y*ml"):
    for d in docs(f):
        if d.get("kind") != "IngressRoute":
            continue
        for r in (d.get("spec") or {}).get("routes") or []:
            for s in r.get("services") or []:
                if s.get("name"):
                    ruteados.add(s["name"])

evaluadas = 0
for app in (root/"seed").iterdir():
    # `plantillas` tampoco es un seed de app: se evalúa aparte, abajo,
    # porque su exposición vive en otro archivo (el contrato template).
    if not app.is_dir() or app.name in ("platform", "templates"):
        continue
    servicios, texts = set(), []
    for f in app.rglob("*.y*ml"):
        texts.append(f.read_text())
        for d in docs(f):
            if d.get("kind") == "Service":
                servicios.add(d["metadata"]["name"])
    if not servicios:
        continue
    evaluadas += 1
    if any("expose: false" in t for t in texts):
        continue
    huerfanos = servicios - ruteados
    if huerfanos:
        print(f"FAIL seed {app.name}: Service(s) {sorted(huerfanos)} sin ninguna "
              f"IngressRoute que los nombre (ni acá ni en la plataforma) "
              f"ni 'expose: false' explícito")
        ok = False
# Las plantillas (caminos/design.md §4) llevan el MISMO invariante en
# OTRA forma: su IngressRoute no puede existir en la semilla porque la
# deriva aegis-org DEL CONTRATO al instanciar (#54 — el kind ni
# siquiera le pertenece al repo de la app). Lo que sí puede y debe
# declarar la plantilla es la exposición: un esqueleto con Service cuyo
# contract.yaml.tpl no dice `publico:` instanciaría apps que nacen
# invisibles — exactamente el CR-5 que este check existe para cazar.
pl = root/"seed"/"templates"
if pl.is_dir():
    for p in sorted(pl.iterdir()):
        if not p.is_dir():
            continue
        servicios, texts = set(), []
        for f in p.rglob("*.y*ml"):
            texts.append(f.read_text())
            for d in docs(f):
                if d.get("kind") == "Service":
                    servicios.add(d["metadata"]["name"])
        if not servicios:
            continue
        evaluadas += 1
        if any("expose: false" in t for t in texts):
            continue
        tpl = p/"contract.yaml.tpl"
        if "publico:" not in (tpl.read_text() if tpl.exists() else ""):
            print(f"FAIL plantilla {p.name}: esqueleto con Service(s) "
                  f"{sorted(servicios)} y contract.yaml.tpl sin `publico:` — "
                  f"toda app instanciada nacería invisible desde el edge (CR-5)")
            ok = False
# Un recorrido que no recorrió nada no es un veredicto: si ningún seed
# declara Services, este check dejó de medir y hay que enterarse.
if evaluadas == 0:
    print("FAIL ningún seed con Service: el check 55 no evaluó nada")
    ok = False
# P2.12: el canary con 1 réplica NO puede tener ventana de rollout:
dep = yaml.safe_load_all((root/"seed"/"canary"/"k8s/base/deployment.yaml").open())
d = next(x for x in dep if x and x.get("kind") == "Deployment")
ru = ((d["spec"].get("strategy") or {}).get("rollingUpdate") or {})
if ru.get("maxUnavailable") != 0:
    print("FAIL canary sin maxUnavailable: 0 (ventana de Bad Gateway con 1 réplica)")
    ok = False
sys.exit(0 if ok else 1)
EOF
then pass "seeds con Service exponen (o declaran expose: false); canary sin ventana de rollout"
else fail "seed nace invisible desde el edge o con downtime de rollout (CR-5/P2.12)"; fi
}
