# titulo: generators KSOPS ↔ productores (A7 estático)
# origen: verify-static.sh (v2) ══ 4
check() {
# TRES PRODUCTORES, no uno (corregido 2026-08-05, #48).
#
# Este check nacía asumiendo que el único productor de secretos son las
# fases del init. Dejó de ser cierto cuando #39/#41 trajeron
# `platform/aegis secret`, que crea los secretos DERIVADOS DE LOS
# CONTRATOS. Con el modelo viejo, seis archivos perfectamente producidos
# salían como "sin productor" — y un check que grita por seis cosas
# sanas es un check que se deja de leer, con lo cual las que sí están
# rotas se pierden en el ruido.
#
#   1. fases del init        make_enc_secret, mención literal
#   2. aegis secret     derivado de orgs/*.yaml (mecanizado: el
#                            material no pasa por la terminal de nadie)
#   3. protocolo MANUAL      declarado abajo, uno por uno, CON el
#                            documento que lo explica — y se comprueba
#                            que el documento exista, para que la
#                            categoría no sea una alfombra
#
# Cualquier cosa fuera de las tres es un secreto que nadie crea: en una
# instancia nueva queda cifrado con una age key que ya no existe, KSOPS
# no lo puede descifrar y su App no sincroniza jamás.
if python3 - "$AEGIS_ROOT" <<'EOF'
import importlib.machinery, importlib.util, re, sys, pathlib, yaml
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# entries declaradas en los generators:
entries = {}   # basename -> dir del generator
dup_falla = False
for g in P.rglob("secret-generator.yaml"):
    doc = yaml.safe_load(g.open())
    files = doc.get("files", [])
    # Una entry DUPLICADA no es inofensiva: kustomize muere con
    # «already registered id» y la App no genera. Pasó en el primer
    # encendido de la fase 85 (2026-08-20): el guard de la fase no veía
    # una entry con comentario al final y la insertaba de nuevo. El
    # dict de abajo colapsaba el duplicado en silencio — por eso este
    # check no lo vio venir y ahora lo caza.
    for f in sorted({x for x in files if files.count(x) > 1}):
        print(f"FAIL entry DUPLICADA en generator: {g.parent.relative_to(P)}/{f}")
        dup_falla = True
    for f in files:
        entries[f] = str(g.parent.relative_to(P))
if dup_falla:
    sys.exit(1)
# productores: TODA mención literal de un *.enc.yaml en las fases
# (cubre make_enc_secret directo Y los que llegan por loop/lista —
# el extractor por firma exacta perdía los de la fase 40):
phases = (root/"init"/"phases")
produced = {}  # basename -> fases que lo mencionan
txt80 = (phases/"80-supply-chain.sh").read_text()
for ph in sorted(phases.glob("*.sh")):
    for m in re.finditer(r'([A-Za-z0-9_./$-]+\.enc\.yaml)', ph.read_text()):
        produced.setdefault(pathlib.Path(m.group(1)).name, []).append(ph.name)

# ── productor 2: el camino derivado de los contratos ──────────────
# Se le PREGUNTA al generador en vez de repetir acá su lista. Los
# nombres se construyen (`secret-<base>-credenciales`,
# `secret-garage-<org>`), así que una lista escrita a mano se
# desincronizaría en cuanto alguien agregue un tipo de secreto — y
# fallaría del lado que no avisa: dando por bueno lo que no existe.
por_contrato = {}   # basename -> por qué
# El generador puede NO ESTAR, y no es un error: la semilla nace sin
# organizaciones. Un clone virgen de aegis-v2 no tiene platform/bin/ ni
# platform/orgs/ hasta que la instancia crezca. Tratar su ausencia como
# fallo haría que este check muriera justo en el artefacto que le toca
# verificar.
hay_generador = (P/"bin"/"aegis-org").is_file()
if not hay_generador:
    print("  (semilla sin organizaciones: no hay camino de contratos que consultar)")
try:
    if not hay_generador:
        raise StopIteration
    spec = importlib.util.spec_from_loader(
        "aegis_org", importlib.machinery.SourceFileLoader(
            "aegis_org", str(P/"bin"/"aegis-org")))
    gen = importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
    for c_ruta in sorted((P/"orgs").glob("*.y*ml")):
        c = yaml.safe_load(c_ruta.open()) or {}
        for s in gen.secretos_de(c):
            por_contrato[s] = f"aegis-secret --todos orgs/{c_ruta.name}"
        # La deploy key con la que ArgoCD lee el repo de la organización.
        # Vive en el namespace de ArgoCD pero es DE LA ORGANIZACIÓN: sale
        # de su `repo:`. La crea la misma pasada de --todos (#48).
        for nombre_app in gen.repos_de(c).values():
            por_contrato[f"secret-{nombre_app}-repo.enc.yaml"] = \
                f"aegis-secret --todos orgs/{c_ruta.name}"
    for org in gen.orgs_con_bucket():
        por_contrato[f"secret-garage-{org}.enc.yaml"] = "aegis-secret --reubicar"
    # de plataforma, con receta propia en aegis-secret:
    por_contrato["secret-garage-credentials.enc.yaml"] = "aegis-secret (receta de plataforma)"
except StopIteration:
    pass
except Exception as e:
    print(f"FAIL no se pudo consultar al generador de contratos: {e}")
    sys.exit(1)

# ── productor 3: protocolos MANUALES, declarados uno por uno ──────
# Se acepta que un secreto se cree a mano SOLO si hay un documento que
# diga cómo. Sin esa exigencia esto sería una lista de excepciones, que
# es como se archiva un problema en vez de resolverlo.
MANUALES = {
    # Archivo COMPARTIDO entre organizaciones: el mapa tenant -> clave
    # que consume el gateway. Editarlo automáticamente significaría que
    # un alta mal tipeada pisa la entrada de otra organización.
    "secret-ai-keys.enc.yaml": "docs/protocols/ai-tenant-key.md",
}
ok = True
# El documento se exige SOLO si el archivo está realmente listado por
# algún generator. La semilla no tiene ai-system —ni ningún subsistema
# que crezca después—, así que exigirle su protocolo sería pedirle
# documentación de algo que todavía no existe.
for archivo, doc in MANUALES.items():
    if archivo in entries and not (P/doc).is_file():
        print(f"FAIL {archivo} se declara manual pero {doc} no existe"); ok = False

for e, d in sorted(entries.items()):
    if e in produced or e in por_contrato or e in MANUALES:
        continue
    print(f"FAIL entry sin productor: {d}/{e}"); ok = False
if por_contrato:
    usados = sorted(set(por_contrato) & set(entries))
    print(f"  (derivados de contratos: {len(usados)} — {', '.join(usados)})")
# entries agregadas EN RUNTIME por su fase productora (patrón
# same-commit, regla temporal — check 18): la fase que produce el
# .enc.yaml DEBE también agregar la línea al generator:
RUNTIME_ENTRY = {
    "secret-cosign-signing-key.enc.yaml":   "80-supply-chain.sh",
}
SPECIAL = set(RUNTIME_ENTRY) | {
    "tokens.enc.yaml",                     # consumidor = wrapper tofu, no KSOPS
}
for p, phs in produced.items():
    if p not in entries and p not in SPECIAL:
        print(f"FAIL productor sin entry de generator: {p} ({phs})"); ok = False
for e, phname in RUNTIME_ENTRY.items():
    t = (phases/phname).read_text()
    if e not in t or "secret-generator.yaml" not in t:
        print(f"FAIL {phname} no agrega la entry runtime {e}"); ok = False
print(f"generators: {len(entries)} entries, {len(produced)} .enc.yaml referenciados")
sys.exit(0 if ok else 1)
EOF
then pass "generators ↔ productores alineados"
else fail "generator/productor desalineados"; fi
}
