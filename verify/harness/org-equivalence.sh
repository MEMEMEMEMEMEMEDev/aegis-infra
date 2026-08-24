#!/usr/bin/env bash
# harness/org-equivalence.sh — la mudanza no cambió una coma.
#
# `aegis-org` son 2858 renglones que derivan del contrato de cada
# organización TODO lo que necesita: bundle, netpol, ruteo, appproject,
# jobs de Jenkins, sondas, buckets. Mudarlo al producto y ponerle un
# paquete debajo (rutas, marcas, conf) es tocar el archivo más caro del
# sistema, y la única prueba que vale es comparar lo que ESCRIBE, byte
# a byte, contra la versión que hoy sirve la tienda de verdad.
#
# Método: tres copias livianas de la instancia de v2 (solo lo que el
# generador lee). En una corre el generador de v2, en otra el de v3, y
# la tercera queda de TESTIGO sin tocar — así el conjunto de archivos
# generados se deriva por comparación en vez de escribirse a mano. La
# instancia real no se toca en ningún momento.
#
# La ÚNICA diferencia admitida está declarada abajo: los archivos
# derivados llevan escrito cómo reaplicarlos, y ese comando cambió de
# nombre. Cualquier otra diferencia es una regresión.
set -u
: "${AEGIS_ROOT:?}"
V2="${AEGIS_V2:-$HOME/Escritorio/workspace/aegis-v2}"
ORG_V2="$V2/platform/bin/aegis-org"
PLAT="$V2/platform"
CONF="$V2/init/aegis-init.conf"

if [[ ! -x "$ORG_V2" || ! -d "$PLAT/orgs" ]]; then
    echo "NO SE PUDO EVALUAR: no encuentro la referencia ($ORG_V2 / $PLAT/orgs)" >&2
    echo "  — con AEGIS_V2=<ruta> se le puede indicar dónde está" >&2
    exit 2
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
armar() {
    local d="$1"
    mkdir -p "$d/ai" "$d/tofu/envs/cloudflare-tunnel" "$d/docs/protocols" "$d/bin"
    cp -a "$PLAT/orgs" "$PLAT/k8s" "$d/"
    cp -a "$PLAT"/*.yaml "$d/"
    cp -a "$PLAT/ai/routes.yaml" "$PLAT/ai/tasks.yaml" "$d/ai/" 2>/dev/null
    cp -a "$PLAT/ai/aprovisionar-bucket.mjs" "$d/ai/" 2>/dev/null
    cp -a "$PLAT/tofu/envs/cloudflare-tunnel/main.tf" "$d/tofu/envs/cloudflare-tunnel/" 2>/dev/null
    cp -a "$PLAT/docs/protocols/templates" "$d/docs/protocols/" 2>/dev/null
    cp -a "$ORG_V2" "$d/bin/"
}
armar "$TMP/v2"; armar "$TMP/v3"; armar "$TMP/base"

CONTRATOS=("$PLAT"/orgs/*.yaml)
[[ -e "${CONTRATOS[0]}" ]] || { echo "NO SE PUDO EVALUAR: cero contratos en $PLAT/orgs" >&2; exit 2; }

v3org() { PLATFORM_DIR="$TMP/v3" AEGIS_CONF="$CONF" AEGIS_ROOT="$AEGIS_ROOT" \
              "$AEGIS_ROOT/libexec/aegis-org" "$@"; }

for c in "${CONTRATOS[@]}"; do
    n="$(basename "$c")"
    ( cd "$TMP/v2" && ./bin/aegis-org aplicar "orgs/$n" ) >/dev/null 2>&1
    v3org apply "$TMP/v3/orgs/$n" >/dev/null 2>&1
done
# y las dos derivaciones globales, que no son por contrato
( cd "$TMP/v2" && ./bin/aegis-org borde && ./bin/aegis-org ruteo ) >/dev/null 2>&1
v3org edge >/dev/null 2>&1
v3org routes >/dev/null 2>&1

export LC_ALL=C

# La diferencia declarada: el nombre del comando en los comentarios de
# lo generado. Se normaliza SOLO al comparar, y SOLO en archivos que el
# generador tocó — un intento anterior lo hizo sobre el árbol entero y
# se inventó diferencias en archivos FUENTE que nadie había generado.
# El renglón del hash también es una diferencia declarada: la huella
# cubre el contrato Y EL GENERADOR que lo renderiza (es lo que detecta
# que un derivado quedó viejo), y el generador cambió a propósito. Se
# compara el CONTENIDO; que la huella cambie es la consecuencia
# correcta, no una regresión.
normalizar() {
    # OJO: acá se citan los nombres VIEJOS a propósito, y por eso van
    # armados por partes. Un `sed -i` masivo de renombre pasó por este
    # archivo y reescribió estas mismas reglas —dejando al harness sin
    # poder reconocer la salida de v2—. El armado por concatenación es
    # feo y es deliberado: que un renombre automático no lo toque.
    local V="bin/aegis-"
    sed -e "s#${V}org aplicar#aegis org apply#g" \
        -e "s#${V}org#aegis org#g" \
        -e "s#${V}secreto --todos#aegis secret create#g" \
        -e "s#${V}secreto#aegis secret create#g" \
        -e "s#${V}chequeo#aegis check#g" \
        -e "s#${V}sync root#aegis sync root#g" \
        -e '/^# hash: sha256:/d' "$1"
}

GEN=0 DISTINTOS=0
while IFS= read -r rel; do
    a="$TMP/v2/$rel"; b="$TMP/v3/$rel"; base="$TMP/base/$rel"
    [[ -f "$a" ]] || { printf '  \033[1;31m✗\033[0m %s: solo lo escribió v3\n' "$rel"; DISTINTOS=$((DISTINTOS+1)); continue; }
    if [[ -f "$base" ]] && cmp -s "$a" "$base" && cmp -s "$b" "$base"; then continue; fi
    GEN=$((GEN+1))
    if ! diff -q <(normalizar "$a") <(sed '/^# hash: sha256:/d' "$b") >/dev/null 2>&1; then
        DISTINTOS=$((DISTINTOS+1))
        if [[ $DISTINTOS -le 3 ]]; then
            printf '  \033[1;31m✗\033[0m %s\n' "$rel"
            diff <(normalizar "$a") <(sed '/^# hash: sha256:/d' "$b") | head -12 | sed 's/^/      /'
        fi
    fi
done < <(cd "$TMP/v3" && find . -type f -not -path './bin/*' | sed 's#^\./##' | sort)

if [[ "$DISTINTOS" == 0 ]]; then
    printf '  \033[1;32m✓\033[0m %s contratos reales renderizados · %s archivos generados · byte a byte idénticos\n' \
        "${#CONTRATOS[@]}" "$GEN"
    exit 0
fi
printf '  %s de %s archivos generados difieren\n' "$DISTINTOS" "$GEN"
exit 1
