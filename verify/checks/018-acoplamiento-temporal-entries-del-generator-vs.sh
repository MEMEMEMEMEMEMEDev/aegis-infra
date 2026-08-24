# title: acoplamiento temporal: entries del generator vs fase de sync
# origen: verify-static.sh (v2) ══ 18
check() {
# Corrida #4 (bug que frenó): un entry estático cuyo .enc.yaml se
# genera en una fase POSTERIOR al primer sync de su App rompe el
# build atómico de kustomize → NINGÚN secret de la App se crea.
# Invariante: fase-productora(entry) ≤ fase-del-primer-argo_sync(App).
# (Apps automated sin sync explícito cuentan como fase 35 — el root
# las crea y el automated sincroniza ahí mismo.)
# REESCRITO el 2026-08-05 (#48). El check tenía dos defectos que lo
# hacían gritar por lo sano y callar sobre lo roto:
#
#   1. INDEXABA POR NOMBRE DE ARCHIVO. Hay siete
#      `secret-regcred-internal.enc.yaml` en directorios distintos, y
#      todos heredaban la fase del único que produce una fase del init
#      (el de org-canary). Seis FAILs por archivos que no tienen nada
#      que ver. Peor: contaba como "productor" los PATRONES DE SED
#      —`sed '/archivo.enc.yaml/a\ ...'` es una dirección, no una
#      escritura— así que atribuía producción a quien solo lee.
#
#   2. TOMABA EL `argo_sync` EXPLÍCITO como primer sync. Una App con
#      `automated` la sincroniza ArgoCD en cuanto root la crea, en la
#      fase 35, haya o no un argo_sync después. Eso SUBESTIMA la
#      ventana.
#
# Y el invariante se afinó en dos niveles, porque no todo lo tardío
# duele igual:
#
#   FATAL      el entry se produce DESPUÉS de un `argo_sync` explícito
#              de su App. Ese sync es un GATE: la fase muere ahí. En
#              un arranque con age key NUEVA el archivo está en git
#              pero cifrado con una llave que ya no existe, KSOPS no
#              lo descifra, y el build falla igual que si faltara.
#   ventana    se produce después del sync AUTOMÁTICO pero antes de
#              cualquier gate. La App queda OutOfSync un rato y
#              `selfHeal` la recupera cuando la fase productora
#              reescribe el archivo. Se informa, no se falla: un rojo
#              permanente apaga la señal igual que un verde falso.
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# App: path -> name, y si es automated (sincroniza sola en la 35):
apps, automated = {}, {}
for f in (P/"k8s"/"argocd-apps").glob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        nom = d["metadata"]["name"]
        automated[nom] = "automated" in (d["spec"].get("syncPolicy") or {})
        for s in (d["spec"].get("sources") or [d["spec"].get("source")]):
            if s and "path" in s:
                apps[s["path"]] = nom
gate_sync = {}   # el argo_sync EXPLÍCITO: es donde la fase se planta
for ph in (root/"init"/"phases").glob("[0-9][0-9]-*.sh"):
    n = int(ph.name[:2])
    for m in re.finditer(r'argo_sync\s+([a-z0-9-]+)', ph.read_text()):
        a = m.group(1)
        gate_sync[a] = min(gate_sync.get(a, 99), n)

# fase productora por RUTA, no por nombre. Las fases nombran destinos
# con variables; se expanden las dos que se usan y se descarta todo lo
# que no termine siendo una ruta real bajo k8s/ (eso deja fuera los
# patrones de sed, que empiezan con '/').
def _rel(s):
    for v in ("$PLATFORM_DIR/", "${PLATFORM_DIR}/"): s = s.replace(v, "")
    for v in ("$B/", "${B}/"): s = s.replace(v, "k8s/base/")
    return s
producer = {}
for ph in (root/"init"/"phases").glob("[0-9][0-9]-*.sh"):
    n = int(ph.name[:2])
    for m in re.finditer(r'([A-Za-z0-9_.${}/-]+\.enc\.yaml)', ph.read_text()):
        r = _rel(m.group(1))
        if r.startswith("k8s/"):
            producer[r] = min(producer.get(r, 99), n)

ok = True; checked = 0; ventanas = []
for g in sorted(P.rglob("secret-generator.yaml")):
    gdir = str(g.parent.relative_to(P))
    app = apps.get(gdir)
    if app is None:
        print(f"FAIL generator sin App que lo incluya: {gdir}"); ok = False
        continue
    gate = gate_sync.get(app, 99)
    auto = 35 if automated.get(app) else 99
    for e in (yaml.safe_load(g.open()) or {}).get("files", []):
        checked += 1
        # NO se exige que el archivo exista ni esté versionado, y es
        # deliberado: EN LA SEED NINGUNO EXISTE. Los crea el init, y
        # después los commitea. Exigirlo daba 12 FAILs contra un clone
        # virgen — o sea contra el artefacto que este verificador
        # existe para verificar. Lo que importa es el ORDEN.
        rel = f"{gdir}/{e}"
        prod = producer.get(rel)
        if prod is None:
            continue   # lo produce el camino de contratos; check 4 lo cubre
        if prod > gate:
            print(f"FAIL acoplamiento temporal: {rel} se produce en fase {prod} "
                  f"pero la fase {gate} SE PLANTA en `argo_sync {app}` — con una "
                  f"age key nueva ese archivo no se descifra y la fase muere ahí")
            ok = False
        elif prod > auto:
            ventanas.append(f"{rel} (fase {prod} > sync automático 35, App {app})")
print(f"entries verificados contra fases de sync: {checked}")
if ventanas:
    print(f"  ventanas recuperables por selfHeal ({len(ventanas)}):")
    for v in ventanas:
        print(f"    - {v}")
# 18b — variante CRD de la misma clase (revisión post-#4): un CR
# cuyo CRD instala un chart de fase POSTERIOR no puede estar estático
# en un kustomization que sincroniza antes. El CR debe (1) NO estar en
# ningún kustomization estático y (2) ser agregado por la fase que
# instala su CRD, en el mismo commit.
#
# HOY NO HAY NINGÚN CASO: el único era el CR del Image Updater y se
# retiró en #59. El guard se conserva a propósito —la trampa vuelve con
# el próximo chart que traiga su propio CRD— y por eso imprime CUÁNTOS
# verificó: "0 verificados" y "todos bien" no se ven igual.
CR_APIS = ("argocd-image-updater.argoproj.io",)
crs = [f for f in P.rglob("*.yaml")
       if f.name != "kustomization.yaml"
       and any(a in f.read_text() for a in CR_APIS)]
f70 = (root/"init"/"phases"/"70-deploy-auto.sh").read_text()
for cr in crs:
    k = cr.parent/"kustomization.yaml"
    # parsear YAML, no grep: el filename aparece legítimamente en el
    # COMENTARIO que documenta esta misma regla:
    kres = (yaml.safe_load(k.open()) or {}).get("resources", []) \
           if k.exists() else []
    if cr.name in kres:
        print(f"FAIL CR con CRD de fase 70 listado ESTÁTICO: "
              f"{cr.relative_to(P)} (rompería el sync previo)"); ok = False
    if cr.name not in f70 or "kustomization.yaml" not in f70:
        print(f"FAIL la fase 70 no agrega {cr.name} al kustomization "
              f"(CR quedaría huérfano — nunca aplicado)"); ok = False
print(f"CRs de CRD-tardío verificados: {len(crs)}")
sys.exit(0 if ok else 1)
EOF
then pass "sin entries de fases futuras al sync de su App (+CRs de CRD tardío)"
else fail "acoplamiento temporal en generators"; fi
}
