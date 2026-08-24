# titulo: AppProjects: cero default + tenant sin cluster-scoped (W-06 / R1-B)
# origen: verify-static.sh (v2) ══ 76
check() {
D76=""
APDIR="$P/k8s/argocd-apps"
APROJ="$P/k8s/bootstrap/appprojects.yaml"
# 1) ninguna Application en project:default — EN TODO platform/k8s
#    (NO solo argocd-apps: el canary se define TAMBIÉN en bundle.yaml —
#    alcance estrecho del check original, clase C15):
DEF76="$(grep -rln 'kind: Application' "$P/k8s" 2>/dev/null \
         | xargs -r grep -l 'project:[[:space:]]*default' 2>/dev/null)"
[[ -z "$DEF76" ]] || D76="$D76 Applications en project:default: $DEF76;"
# 2) los 3 AppProjects existen
for p in aegis-bootstrap aegis-platform aegis-tenant-canary; do
    grep -q "name: $p" "$APROJ" 2>/dev/null || D76="$D76 falta AppProject $p;"
done
# 3) INVARIANTE R1-B: el proyecto del tenant NIEGA cluster-scoped
#    (clusterResourceWhitelist vacío) — el invariante, no un string:
TEN76="$(awk '/name: aegis-tenant-canary/,0' "$APROJ")"
echo "$TEN76" | grep -Eq 'clusterResourceWhitelist:[[:space:]]*\[\]' \
    || D76="$D76 aegis-tenant-canary no niega cluster-scoped (clusterResourceWhitelist debe ser []);"
# aegis-platform usa namespace '*' (los charts crean RBAC fuera de su ns
# — cert-manager en kube-system; enumerar = whack-a-mole por corrida, v1):
PLAT76="$(awk '/name: aegis-platform/,/name: aegis-tenant-canary/' "$APROJ")"
echo "$PLAT76" | grep -qF "namespace: '*'" \
    || D76="$D76 aegis-platform no usa namespace '*' (se re-narrowó — los charts rompen el sync);"
# 4) el canary corre bajo un proyecto de TENANT y no bajo el de
#    plataforma. Lo que importa es el proyecto, NO en qué archivo esté
#    declarada la App: hasta 2026-07-28 este sub-check miraba solo
#    ci-supply-tenants.yaml, y cuando la App se movió al bundle de su
#    organización —que es donde vive el dueño único— dio FAIL sin que
#    el invariante se hubiera roto. Misma clase C15 que ya obligó a
#    ensanchar el sub-check 1: un check atado a la UBICACIÓN miente en
#    cuanto algo se mueve. Se busca en todo platform/k8s:
grep -rq 'project:[[:space:]]*aegis-tenant-canary' "$P/k8s" 2>/dev/null \
    || D76="$D76 ninguna App en aegis-tenant-canary (el canary quedó en el proyecto de plataforma);"
# 5) la 35 aplica los AppProjects ANTES de root (clase C1)
L_AP="$(grep -n 'appprojects.yaml' "$FASES/35-gitops.sh" | head -1 | cut -d: -f1)"
L_ROOT="$(grep -n 'argocd-apps/root.yaml' "$FASES/35-gitops.sh" | head -1 | cut -d: -f1)"
if [[ -z "$L_AP" || -z "$L_ROOT" ]] || (( L_AP > L_ROOT )); then
    D76="$D76 la 35 no aplica los AppProjects antes de root (o falta);"
fi
# 5b) y aplica TAMBIÉN los derivados, antes de root (#19). Sin esta
#     línea el bootstrap crea los proyectos del sustrato, root sincroniza,
#     y las Applications de las organizaciones quedan "project not found".
L_APT="$(grep -n 'appprojects-tenants.yaml' "$FASES/35-gitops.sh" | head -1 | cut -d: -f1)"
if [[ -z "$L_APT" ]] || (( L_APT > L_ROOT )); then
    D76="$D76 la 35 no aplica appprojects-tenants.yaml antes de root (o falta);"
fi
# 6) EL INVARIANTE QUE FALTABA (#19): todo proyecto que una Application
#    referencia tiene que estar DEFINIDO en alguno de los dos archivos.
#
#    Hasta el 2026-08-05 los AppProjects de tenant se escribían a mano,
#    así que dar de alta una organización era: contrato, generador,
#    push... y acordarse de un archivo más. Nada lo comprobaba. El
#    síntoma llega tarde y lejos —la app existe, el pipeline construye,
#    y ArgoCD dice "project not found" recién al desplegar—, y llega
#    solo si alguien mira. Esto lo caza en un clone, sin cluster.
#
#    Se comprueba el INVARIANTE (referencia ⊆ definición), no una lista
#    de nombres: una lista sería el quinto lugar donde acordarse.
#
#    OJO CON LA RUTA. Hasta el 2026-08-11 este bloque caminaba
#    `platform/k8s` —la INSTANCIA— mientras el resto del check 76 ya
#    miraba la semilla. Es el mismo error que documenta la cabecera de
#    este archivo, y con el agravante de siempre: `platform/` está en
#    .gitignore, así que en un clone limpio no existe, `os.walk` sobre
#    un directorio ausente no itera, los dos conjuntos quedan vacíos y
#    "no hay huérfanas" sale VERDE por no haber mirado. Por eso abajo
#    se exige haber encontrado al menos una Application: un recorrido
#    que no recorrió nada no es un veredicto.
python3 - "$AEGIS_ROOT" <<'PY' || D76="$D76 hay Applications que referencian un AppProject que nadie define;"
import os, re, sys
raiz = os.path.join(sys.argv[1], "seed", "platform", "k8s")
if not os.path.isdir(raiz):
    print(f"    no existe {raiz}: el check no puede opinar", file=sys.stderr)
    sys.exit(1)
definidos, referencias = set(), {}
for base, _, archivos in os.walk(raiz):
    for a in archivos:
        if not a.endswith((".yaml", ".yml")):
            continue
        ruta = os.path.join(base, a)
        try:
            txt = open(ruta, encoding="utf-8").read()
        except OSError:
            continue
        # Se lee con regex y no con yaml.safe_load a propósito: buena
        # parte de estos archivos son plantillas de kustomize/helm que
        # no parsean como YAML suelto. El invariante no necesita el
        # árbol, necesita los dos conjuntos.
        if "kind: AppProject" in txt:
            definidos |= set(re.findall(r"^\s+name:\s*(\S+)", txt, re.M))
        if "kind: Application" in txt:
            for p in re.findall(r"^\s*project:\s*(\S+)", txt, re.M):
                referencias.setdefault(p, set()).add(os.path.relpath(ruta, raiz))
if not referencias:
    print("    cero Applications encontradas: el invariante no se evaluó", file=sys.stderr)
    sys.exit(1)
huerfanas = {p: v for p, v in referencias.items() if p not in definidos}
if huerfanas:
    for p, donde in sorted(huerfanas.items()):
        print(f"    proyecto '{p}' referenciado por {sorted(donde)} y definido en NINGÚN lado",
              file=sys.stderr)
    sys.exit(1)
PY
if [[ -n "$D76" ]]; then fail "appprojects:$D76"
else pass "Apps en AppProjects definidos; tenant deny cluster-scoped; proyectos (fijos y derivados) antes que root"; fi
}
