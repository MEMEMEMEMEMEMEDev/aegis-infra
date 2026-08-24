# titulo: arrancar con CERO organizaciones no es un caso de borde
# origen: verify-static.sh (v2) ══ 87
check() {
# Los dos manifiestos de organizaciones los DERIVA `bin/aegis-org` de
# orgs/*.yaml, y una instancia recién arrancada no tiene contratos: los
# dos existen con su encabezado y sin un solo documento. Ese es el
# estado normal del día uno, no una anomalía.
#
# Pero `kubectl apply -f` sobre un archivo sin objetos NO es un no-op:
#
#     error: no objects passed to apply     (rc 1)
#
# y con set -e mata la fase 35. O sea que la semilla no arrancaría por
# ser correcta. Este check cubre las tres piezas del arreglo.
D87=""
APT87="$P/k8s/bootstrap/appprojects-tenants.yaml"
TEN87="$P/k8s/argocd-apps/tenants.yaml"
# 1) los dos archivos EXISTEN versionados: la 35 aplica el primero, y un
#    archivo ausente ahí es un error de arranque distinto y peor.
for f87 in "$APT87" "$TEN87"; do
    [[ -f "$f87" ]] || D87="$D87 falta ${f87#"$P"/} (lo deriva el generador, pero tiene que existir versionado);"
done
# 2) y llegan SIN documentos: los contratos de otra instancia no viajan.
if [[ -f "$APT87" ]]; then
    N87="$(python3 -c 'import sys,yaml; print(len([d for d in yaml.safe_load_all(open(sys.argv[1])) if d]))' "$APT87" 2>/dev/null)"
    [[ "$N87" == "0" ]] || D87="$D87 appprojects-tenants.yaml de la semilla trae $N87 documento(s): son organizaciones de otra instancia;"
fi
# 3) el helper existe y la 35 GUARDA el apply con él. Se mira que el
#    guard y el apply estén en la misma línea lógica: que exista
#    yaml_has_docs en algún lado del archivo no prueba que proteja a
#    ESTE apply.
grep -q '^yaml_has_docs()' "$LIBS/common.sh" \
    || D87="$D87 falta yaml_has_docs en common.sh;"
grep -qE '^\s*if\s+yaml_has_docs\s+"\$PLATFORM_DIR/k8s/bootstrap/appprojects-tenants\.yaml"' \
     "$FASES/35-gitops.sh" \
    || D87="$D87 la 35 aplica appprojects-tenants.yaml sin preguntar si tiene documentos;"
# 4) el TERCER derivado, que no es un archivo entero sino una REGIÓN
#    (agregado 2026-08-22 con la derivación de sondas). vmagent/
#    values.yaml es mitad producto y mitad generado: `aegis-org` le
#    escribe una sonda por organización entre dos marcas.
#
#    Aquí el des-renderizado NO alcanza y por eso hizo falta este
#    punto. `traer` convirtió blog.example.com en
#    blog.__ROOT_DOMAIN__ —el guard de aegis dev seed pasó feliz, el
#    valor de esta instancia ya no estaba— pero los NOMBRES de las
#    organizaciones se quedaron. La semilla quedó sondeando blog,
#    ejemplo, portafolio y shop: cuatro sitios que en una instancia
#    nueva no existen, cuatro probes en rojo permanente y cuatro
#    SitioDeInquilinoCaido el día uno. El falso rojo crónico, de
#    fábrica, en el estreno del producto.
VMA87="$P/k8s/base/observability/vmagent/values.yaml"
if [[ ! -f "$VMA87" ]]; then
    D87="$D87 falta ${VMA87#"$P"/};"
else
    N87S="$(python3 - "$VMA87" <<'PY'
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
i = t.find("# --- DERIVED by aegis-org (tenant probes): do not edit by hand ---")
f = t.find("# --- END DERIVED ---")
print(-1 if i < 0 or f < 0 else len(re.findall(r"^\s*-\s*job_name:", t[i:f], re.M)))
PY
)"
    [[ "$N87S" == "-1" ]] \
        && D87="$D87 vmagent/values.yaml perdió las marcas del bloque derivado: sin el ancla, aegis-org no tiene dónde escribir las sondas;"
    [[ "$N87S" == "0" || "$N87S" == "-1" ]] \
        || D87="$D87 el bloque derivado de vmagent/values.yaml trae $N87S sonda(s): son organizaciones de otra instancia, y en la nueva no existen (rojo permanente desde el arranque);"
fi
if [[ -n "$D87" ]]; then fail "arranque con 0 organizaciones:$D87"
else pass "los 3 derivados de la semilla llegan vacíos (2 manifiestos sin documentos + el bloque de sondas de vmagent) y la 35 guarda su apply con yaml_has_docs"; fi
}
