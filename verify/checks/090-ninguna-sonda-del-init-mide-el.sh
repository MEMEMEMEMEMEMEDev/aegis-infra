# titulo: ninguna sonda del init mide el borde de Cloudflare creyendo medir el cluster (#87)
# origen: verify-static.sh (v2) ══ 90
check() {
# El defecto que este check existe para impedir, medido el 2026-08-13:
# desde que Access está delante de argocd.<dom> y jenkins.<dom> (#76),
# un curl desnudo a esos hostnames recibe un 302 que sirve CLOUDFLARE
# — no entra al túnel, no toca traefik, no ve la app. El gate
# "edge-responde" de la fase 35 aceptaba `30[12]`, así que pasaba en
# verde con el cluster entero apagado.
#
# La lista de hostnames protegidos se DERIVA del módulo de tofu, no se
# hornea acá: el día que alguien ponga un tercer hostname detrás de
# Access, este check lo cubre solo. Hornearla sería C15 — un chequeo
# atado a una lista miente apenas la lista cambia.
D90=""
# Salía de $ROOT/platform — la INSTANCIA. Ver la nota del check 26:
# con producto e instancia en la misma carpeta la ruta equivocada daba
# el mismo resultado. El artefacto es la SEED.
ACCESS_MOD="$P/tofu/modules/cloudflare-access"
if [[ ! -f "$ACCESS_MOD/main.tf" ]]; then
    D90="$D90 no existe el módulo cloudflare-access: no se pudo derivar qué hostnames están protegidos;"
else
    # prefijos de los `domain` de las applications: "argocd.${var...}".
    # De TODOS los .tf del módulo y no solo de main.tf: HCL fusiona el
    # directorio, y una application en archivo propio (grafana.tf,
    # fase-85 §5) quedaría fuera de la lista con su hostname YA
    # protegido — una sonda que lo curlee desnudo pasaría en verde.
    # (El hallazgo anotado en fase-85 §5 era FUNDADO: esto leía solo
    # main.tf hasta el 2026-08-20.)
    PROTEGIDOS="$(grep -hoE '^\s*domain\s*=\s*"[a-z0-9-]+\.\$\{var\.root_domain\}' "$ACCESS_MOD"/*.tf \
                  | sed -E 's/.*"([a-z0-9-]+)\..*/\1/' | sort -u)"
    [[ -n "$PROTEGIDOS" ]] \
        || D90="$D90 el módulo de Access no declara ningún domain reconocible (¿cambió la forma?);"
    for FASE in "$FASES"/*.sh; do
        # se unen continuaciones y se descartan comentarios: el defecto
        # vive en el código, y un ejemplo dentro de un comentario no es
        # un defecto (H4/check 41 — jamás grep de un nombre a secas).
        CUERPO="$(joincont "$FASE" | nc)"
        for H in $PROTEGIDOS; do
            # líneas que curlean ESE hostname sin pasar por el helper:
            MALAS="$(printf '%s\n' "$CUERPO" \
                     | grep -E "curl[^|]*https://$H\.\\\$(\{)?ROOT_DOMAIN" \
                     | grep -v 'edge_origen_responde' || true)"
            [[ -z "$MALAS" ]] \
                || D90="$D90 $(basename "$FASE") curlea $H.\$ROOT_DOMAIN sin edge_origen_responde (bajo Access eso mide el borde de CF);"
        done
    done
    # y el helper tiene que distinguir de verdad: si no mira a dónde
    # redirige, es un curl con otro nombre.
    grep -q 'cloudflareaccess\.com' "$LIBS/access.sh" 2>/dev/null \
        || D90="$D90 edge_origen_responde no distingue el redirect a cloudflareaccess.com — no separa «Access interceptó» de «el origen contestó»;"
fi
if [[ -n "$D90" ]]; then fail "sondas bajo Access:$D90"
else pass "las sondas del init contra los $(printf '%s' "$PROTEGIDOS" | wc -w) hostnames bajo Access pasan por edge_origen_responde, que separa origen de borde"; fi
}
