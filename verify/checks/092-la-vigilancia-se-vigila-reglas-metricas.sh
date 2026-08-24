# titulo: la vigilancia se vigila: reglas ↔ métricas ↔ jobs ↔ paneles
# origen: verify-static.sh (v2) ══ 92
check() {
# Hasta hoy este verificador tenía CERO checks de observabilidad, y el
# barrido del 2026-08-22 encontró nueve defectos en el stack. De los
# nueve, la mayoría eran ESTÁTICAMENTE DETECTABLES — no hacía falta un
# cluster para verlos, hacía falta mirar. Ninguno era una caída: los
# nueve eran la misma enfermedad, un instrumento que informa salud sin
# haber medido nada.
#
# Ese es el punto ciego que este check cubre. Un panel, una alerta y un
# scrape no fallan cuando se rompen: se quedan VACÍOS, y el vacío se
# lee igual que el verde. El único modo de verlo sin cluster es cruzar
# las cuatro capas entre sí y exigir que cada una tenga sujeto en la
# siguiente.
#
# Las diez comprobaciones, y cada una nombra el defecto REAL que la
# trajo (probadas por reintroducción: 12 mutaciones, 12 cazadas):
#
#   1. el bloque DERIVADO de sondas cae dentro de config.scrape_configs.
#      Escrito con 8 espacios en vez de 4 el YAML parsea igual y los
#      jobs no existen — ArgoCD Synced, blackbox ocioso, nadie avisa.
#   2. todo panel apunta a un datasource que grafana PROVISIONA, y todo
#      dashboard lleva el label con el que el sidecar lo recoge.
#   3. toda alerta que COMPARA contra un valor tiene, en su archivo, una
#      hermana con absent(). Sin ella la serie que desaparece no da
#      falso: da vacío, y una alerta vacía no dispara nunca. Las
#      excepciones van declaradas UNA POR UNA con su porqué.
#   4. toda métrica propia que se lee la produce alguien del árbol...
#   5. ...y toda métrica que el árbol produce la lee alguien. Medir y no
#      mirar es el caso (d) del barrido: se paga el costo y no hay señal.
#   6. toda métrica ESCASA (pushada por un CronJob) se lee con
#      last_over_time y una ventana de al menos dos períodos. Sin eso la
#      instant-query cae entre dos pushes y devuelve vacío: fue el
#      falso positivo diario de TrivyDBSinMedida.
#   7. todo job citado en una regla o un panel existe en vmagent.
#   8. el umbral horneado de JobDeScrapeDesaparecido == cuántos jobs de
#      plataforma declara vmagent. Un número a mano envejece solo.
#   9. vmalert y vmagent declaran recarga en caliente. Sin ella una
#      regla commiteada y sincronizada NO ESTÁ CARGADA.
#  10. vmagent con Recreate: su buffer es un PVC RWO con lock exclusivo
#      y con RollingUpdate el rollout entra en CrashLoop para siempre.
D92=""
python3 - "$P" "$AEGIS_ROOT/lib/aegis/org.py" <<'PY' || D92="$D92 (ver detalle arriba);"
import json, re, sys, pathlib, yaml

P = pathlib.Path(sys.argv[1])
OBS = P / "k8s/base/observability"
# En v2 el generador vivía DENTRO del artefacto (seed/platform/
# bin/). En v3 el código vive en el producto y la semilla es artefacto
# puro (02 §1, V-134): el generador de sondas se busca en libexec/.
GENERADOR = pathlib.Path(sys.argv[2])
if not OBS.is_dir():
    print(f"    no existe {OBS}: no hay observabilidad que cruzar", file=sys.stderr)
    sys.exit(1)
malo = []

# ── 1. inventario: los scrape_configs de vmagent ────────────────────
vmag_txt = (OBS / "vmagent/values.yaml").read_text()
vmag = yaml.safe_load(vmag_txt)
jobs = [j["job_name"] for j in vmag["config"]["scrape_configs"]]

MARCA_INI = "# --- DERIVADO por aegis-org (sondas de tenant): no editar a mano ---"
MARCA_FIN = "# --- FIN DERIVADO ---"
i, f = vmag_txt.find(MARCA_INI), vmag_txt.find(MARCA_FIN)
if i < 0 or f < 0:
    malo.append("vmagent/values.yaml: faltan las marcas del bloque que deriva aegis-org "
                "— sin ellas el generador no tiene dónde escribir las sondas")
    derivados, jobs_base = [], jobs
else:
    derivados = re.findall(r"^\s*-\s*job_name:\s*(\S+)", vmag_txt[i:f], re.M)
    jobs_base = [j for j in jobs if j not in derivados]
    for d in derivados:
        if d not in jobs:
            malo.append(f"el job derivado {d!r} está entre las marcas pero NO cae dentro "
                        "de config.scrape_configs: la indentación equivocada parsea como "
                        "YAML válido y deja el job fuera, sin una sola queja")

# En la semilla el bloque derivado está VACÍO —no hay contratos, y ése
# es el estado normal del día uno (check 87)—, así que las reglas de
# inquilinos apuntan a jobs que HOY no existen y existirán en cuanto
# haya una organización. Para distinguir «todavía no tiene sujeto» de
# «apunta a un job que nadie declara», el patrón que emite el generador
# se LEE del generador. Hornearlo acá sería la misma trampa que este
# check persigue: una copia que envejece sola.
# El generador dejó de ser un ejecutable y es un módulo del paquete
# (lib/aegis/org.py): `aegis org` es ahora 34 renglones de argparse
# encima. Este check mide el GENERADOR, así que sigue al cuerpo, no al
# nombre del archivo.
GEN = GENERADOR
generables = []
if GEN.is_file():
    generables = [re.sub(r"\{[a-z_]+\}", "xx", m)
                  for m in re.findall(r"job_name:\s*(\S*\{[a-z_]+\}\S*)", GEN.read_text())]
if not generables:
    malo.append(f"{GEN} no declara ningún job_name derivable: si el generador dejó de "
                "emitir sondas, las reglas de inquilinos quedaron sin sujeto posible")

# Y el módulo que cada sonda pide tiene que existir en blackbox: pedir
# uno inexistente no es un error de arranque, es un probe_success=0
# permanente — indistinguible de «el sitio está caído».
bb = [d for d in yaml.safe_load_all((OBS / "blackbox.yaml").read_text())
      if isinstance(d, dict) and d.get("kind") == "ConfigMap"]
modulos = {m for d in bb for m in yaml.safe_load(d["data"]["config.yml"])["modules"]}
usados = set(re.findall(r"module:\s*\[([a-z0-9_]+)\]", vmag_txt))
if GEN.is_file():
    usados |= set(re.findall(r"module:\s*\[([a-z0-9_]+)\]", GEN.read_text()))
for m in sorted(usados - modulos):
    malo.append(f"una sonda pide el módulo {m!r} de blackbox y blackbox.yaml no lo define: "
                "el probe devuelve 0 para siempre, que se lee igual que «el sitio se cayó»")

# ── 2. inventario: métricas propias que el árbol PRODUCE ────────────
# Se derivan del productor (quien pushea a /api/v1/import/prometheus),
# nunca de una lista acá: una lista a mano se desincroniza y este check
# pasaría a medir su propia copia en vez del artefacto.
#
# Hay dos clases de productor y la diferencia es la CADENCIA, que es lo
# que decide la ventana mínima con la que se puede leer:
#  · cron  — período derivable del schedule. Ventana ≥ 2 períodos.
#  · build — no hay período: un repo puede pasar semanas sin uno. El
#    piso es una POLÍTICA (una semana), no el espejo de un valor que
#    viva en otro lado: por eso va escrito acá y no derivado.
PISO_BUILD = 7 * 86400
productores = {}   # metrica -> (archivo, clase, minimo_seg)
for y in sorted((P / "k8s").rglob("*.yaml")):
    txt = y.read_text()
    if "/api/v1/import/prometheus" not in txt:
        continue
    for d in [d for d in yaml.safe_load_all(txt) if isinstance(d, dict)]:
        if d.get("kind") != "CronJob":
            continue
        sched = d["spec"]["schedule"]
        c, per = sched.split(), None
        if len(c) == 5:
            m, h = c[0], c[1]
            if h == "*" and re.fullmatch(r"\d+", m):                  per = 3600
            elif h.startswith("*/") and re.fullmatch(r"\d+", m):      per = int(h[2:]) * 3600
            elif m.startswith("*/") and h == "*":                     per = int(m[2:]) * 60
            elif re.fullmatch(r"\d+", h) and re.fullmatch(r"\d+", m): per = 86400
        if per is None:
            malo.append(f"{y.name}: no se pudo derivar el período del cron {sched!r} — sin "
                        "período no hay ventana mínima que exigirle a quien lo lea")
            continue
        for met in set(re.findall(r"\b(aegis_[a-z0-9_]+)\b", txt)):
            productores.setdefault(met, (str(y.relative_to(P)),
                                         f"cron cada {per}s", 2 * per))
for jf in sorted((P / "docs/protocols/templates").glob("Jenkinsfile*")):
    txt = jf.read_text()
    if "/api/v1/import/prometheus" not in txt:
        continue
    for met in set(re.findall(r"\b(aegis_[a-z0-9_]+)\{", txt)):
        productores.setdefault(met, (str(jf.relative_to(P)), "cada build", PISO_BUILD))

# ── 3. las reglas ───────────────────────────────────────────────────
cm = yaml.safe_load((OBS / "rules/vmalert-rules.yaml").read_text())
alertas = [(key, r["alert"], r["expr"])
           for key, cuerpo in cm["data"].items()
           for g in yaml.safe_load(cuerpo)["groups"]
           for r in g.get("rules", [])]

# ── 4. los dashboards y los datasources provisionados ───────────────
graf = yaml.safe_load((OBS / "grafana/values.yaml").read_text())
uids_ds = {ds["uid"] for ds in graf["datasources"]["datasources.yaml"]["datasources"]}
paneles = []
n_dash = 0
for dash in sorted((OBS / "dashboards").glob("*.yaml")):
    n_dash += 1
    d = yaml.safe_load(dash.read_text())
    if d.get("metadata", {}).get("labels", {}).get("grafana_dashboard") != "1":
        malo.append(f"dashboards/{dash.name}: sin el label grafana_dashboard=1 el sidecar "
                    "no lo recoge y el dashboard sencillamente no existe en Grafana")
    for nombre, crudo in d["data"].items():
        j = json.loads(crudo)
        if j.get("editable") is not False:
            malo.append(f"dashboards/{dash.name}: {nombre} no declara editable:false "
                        "(design.md §4.1: ninguno nace ni cambia a click)")
        for pan in j["panels"]:
            uid = pan.get("datasource", {}).get("uid")
            if uid not in uids_ds:
                malo.append(f"dashboards/{dash.name}: el panel {pan['title']!r} apunta al "
                            f"datasource {uid!r} y grafana/values.yaml no lo provisiona — "
                            "renderiza vacío para siempre, que es como se ve el verde")
            for t in pan.get("targets", []):
                paneles.append((dash.name, pan["title"], t.get("expr", "")))
                # omitirlo es legítimo (hereda el del panel); declarar
                # OTRO manda la consulta a un store sin esa serie:
                suyo = t.get("datasource", {}).get("uid")
                if suyo is not None and suyo != uid:
                    malo.append(f"dashboards/{dash.name}: el panel {pan['title']!r} lee de "
                                f"{uid!r} y su consulta de {suyo!r}")

# ── 5. toda alerta que compara tiene guardia de ausencia ────────────
SIN_GUARDIA = {
    "DeadmanAegis": "vector(1) no depende de ninguna serie",
    "InquilinoAlLimiteDeMemoria":
        "cero organizaciones es el estado normal del día uno; la desaparición del "
        "inquilino la cubre SitioDeInquilinoSinSonda, que es su misma familia",
    "TargetDeScrapeCaido":
        "la ausencia de `up` entera la cubre JobDeScrapeDesaparecido",
    "JobDeScrapeDesaparecido":
        "ES la guardia: cuenta jobs descubiertos en vez de mirar valores, que es "
        "justo lo que absent() no sabe hacer job por job",
    "KyvernoAdmisionRechazadaEnTenant":
        "increase() sobre un contador: sin rechazos no hay serie, y eso ES la salud. "
        "La desaparición del job la cubre JobDeScrapeDesaparecido",
    "ImagenSinEscaneo":
        "la ausencia es el día uno: una plataforma recién nacida no tiene builds. Un "
        "absent() acá gritaría desde el arranque hasta el primer build, que es el falso "
        "rojo crónico. El caso «desplegada y sin medir» lo reporta aegis check, "
        "que sabe cruzar contra lo que hay corriendo",
    "ImagenSinFirma": "misma razón que ImagenSinEscaneo",
}
METRICA = re.compile(r"\b([a-z][a-z0-9_]+)\s*(?:\{|\[|\)|\s|$)")
PALABRAS = {"time", "sum", "max", "min", "avg", "count", "rate", "increase", "absent",
            "last_over_time", "max_over_time", "min_over_time", "avg_over_time",
            "vector", "by", "without", "and", "or", "unless", "topk", "bottomk",
            "clamp_max", "clamp_min", "on", "ignoring", "group_left", "group_right"}

def metricas_de(expr):
    return {m for m in METRICA.findall(re.sub(r"\{[^}]*\}", " ", expr))
            if m not in PALABRAS and not re.fullmatch(r"\d+[a-z]", m)}

def sujetos_de(expr):
    """Qué mide una expr: sus métricas Y los jobs que filtra.

    Las dos cosas cuentan, porque la guardia puede estar puesta sobre
    una métrica HERMANA del mismo job: si blackbox deja de sondear el
    registry desaparecen probe_success y probe_ssl_earliest_cert_expiry
    JUNTAS, así que un absent() sobre la primera protege a la segunda.
    Exigir la misma métrica sería pedir una alerta por serie, y eso no
    lo sostiene nadie — un check que pide lo insostenible se apaga.
    """
    return metricas_de(expr) | {v for _, v in re.findall(r'job\s*(=~|=)\s*"([^"]+)"', expr)}

guardias = {}
for arch, nom, expr in alertas:
    for a in re.findall(r"absent\(([^)]*(?:\)[^)]*)*?)\)", expr):
        guardias.setdefault(arch, set()).update(sujetos_de(a))
for arch, nom, expr in alertas:
    if "absent(" in expr or nom in SIN_GUARDIA:
        continue
    if not re.search(r"(==|!=|>=|<=|>|<)", expr):
        continue
    suj = sujetos_de(expr)
    if not suj & guardias.get(arch, set()):
        malo.append(f"la alerta {nom} ({arch}) compara contra un valor y ninguna alerta de "
                    f"su archivo guarda con absent() nada de lo que mide ({sorted(suj)}): "
                    "si la serie desaparece no da falso, da vacío, y el vacío no dispara")
declaradas = {n for _, n, _ in alertas}
for nom in SIN_GUARDIA:
    if nom not in declaradas:
        malo.append(f"la excepción declarada para {nom} ya no tiene sujeto: esa alerta no "
                    "existe. Borrala de SIN_GUARDIA o arreglá el nombre")

# ── 6/7. las métricas propias: leídas ↔ producidas ──────────────────
leidas = set()
for arch, nom, expr in alertas:
    leidas |= {m for m in metricas_de(expr) if m.startswith("aegis_")}
for dash, tit, expr in paneles:
    leidas |= set(re.findall(r"\b(aegis_[a-z0-9_]+)\b", expr))
for m in sorted(leidas - set(productores)):
    malo.append(f"la métrica {m} se lee en reglas o paneles y NADIE del árbol la produce: "
                "el panel queda vacío y la alerta no dispara jamás")
for m in sorted(set(productores) - leidas):
    malo.append(f"la métrica {m} la produce {productores[m][0]} y no la lee ni una regla "
                "ni un panel: se paga por medirla y nadie la mira")

# ── 8. métrica escasa: siempre con ventana de ≥ 2 períodos ──────────
SEG = {"s": 1, "m": 60, "h": 3600, "d": 86400}
lectores = ([(f"la alerta {n}", e) for _, n, e in alertas]
            + [(f"el panel {t!r} de {d}", e) for d, t, e in paneles])
for m, (arch, cadencia, minimo) in sorted(productores.items()):
    for donde, expr in lectores:
        if m not in expr:
            continue
        vent = re.findall(rf"last_over_time\(\s*{m}[^)]*\[(\d+)([smhd])\]", expr)
        if not vent:
            malo.append(f"{donde} lee {m} sin last_over_time: {arch} la pushea {cadencia} y "
                        "la ventana por defecto de una instant-query es más corta — la "
                        "consulta cae entre dos pushes y devuelve vacío")
            continue
        for n, u in vent:
            if int(n) * SEG[u] < minimo:
                malo.append(f"{donde}: la ventana [{n}{u}] no llega al mínimo de "
                            f"{minimo}s para una métrica que {arch} pushea {cadencia} — "
                            "un push tarde y la serie desaparece de la consulta")

# ── 9. todo job citado existe ───────────────────────────────────────
for donde, expr in lectores:
    for op, val in re.findall(r'job\s*(=~|=)\s*"([^"]+)"', expr):
        if op == "=" and val not in jobs:
            malo.append(f'{donde} filtra job="{val}" y vmagent no declara ese job_name: '
                        "la consulta no devuelve nada, y no lo va a decir")
        if op == "=~" and not any(re.fullmatch(val, j) for j in jobs):
            if any(re.fullmatch(val, g) for g in generables):
                continue      # sin sujeto HOY; lo tendrá con la 1ª organización
            malo.append(f'{donde} filtra job=~"{val}": ningún job_name de vmagent coincide '
                        "y tampoco es un patrón que aegis-org sepa derivar")

# ── 10. el umbral horneado se deriva, no se recuerda ────────────────
for arch, nom, expr in alertas:
    if nom != "JobDeScrapeDesaparecido":
        continue
    m = re.search(r"<\s*(\d+)", expr)
    if not m:
        malo.append("JobDeScrapeDesaparecido dejó de comparar contra un número de jobs")
    elif int(m.group(1)) != len(jobs_base):
        malo.append(f"JobDeScrapeDesaparecido espera {m.group(1)} jobs y vmagent declara "
                    f"{len(jobs_base)} de plataforma: el umbral quedó viejo, así que o "
                    "grita de más o tapa un job perdido")

# ── 11. recarga en caliente y la estrategia del rollout ─────────────
if vmag.get("extraArgs", {}).get("promscrape.configCheckInterval") is None:
    malo.append("vmagent sin promscrape.configCheckInterval: la sonda que derive aegis-org "
                "queda escrita en el ConfigMap y nadie la raspa")
if vmag.get("deployment", {}).get("spec", {}).get("strategy", {}).get("type") != "Recreate":
    malo.append("vmagent sin deployment.spec.strategy.type=Recreate: su buffer es un PVC "
                "RWO con lock exclusivo y el pod nuevo entra en CrashLoop contra el viejo")
vmal = yaml.safe_load((OBS / "vmalert/values.yaml").read_text())
if vmal["server"].get("extraArgs", {}).get("configCheckInterval") is None:
    malo.append("vmalert sin configCheckInterval: una regla commiteada y sincronizada NO "
                "está cargada hasta que alguien reinicie el pod por otro motivo")

print(f"    {len(jobs)} jobs de scrape ({len(jobs_base)} de plataforma + {len(derivados)} "
      f"derivados), {len(alertas)} alertas en {len(cm['data'])} familias, "
      f"{len(paneles)} consultas en {n_dash} dashboards, "
      f"{len(productores)} métricas propias", file=sys.stderr)
for m in malo:
    print(f"    {m}", file=sys.stderr)
sys.exit(1 if malo else 0)
PY
if [[ -n "$D92" ]]; then fail "la vigilancia no se sostiene sola:$D92"
else pass "reglas, métricas, jobs y paneles se cruzan sin huecos: ninguna alerta compara sin guardia de ausencia, ninguna consulta apunta a un job o un datasource que no existe, y las dos recargas en caliente están declaradas"; fi
}
