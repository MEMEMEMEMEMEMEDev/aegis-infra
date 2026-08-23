#!/usr/bin/env bash
# lib/access.sh — atravesar Cloudflare Access, con UNA implementación
# para el init y para aegis-rotate.
#
# ═══ POR QUÉ EXISTE (#87) ══════════════════════════════════════════
#
# Desde #76, Access está delante de argocd.<dom> y jenkins.<dom>. A
# partir de ahí, TODA sonda del init contra esos hostnames dejó de
# medir lo que cree medir. Medido el 2026-08-13:
#
#   $ curl -sI https://argocd.<dom>/
#   HTTP/2 302
#   location: https://<team>.cloudflareaccess.com/cdn-cgi/access/login/...
#   server: cloudflare
#   cf-ray: a2a8aeae4ee814b1-GIG
#
# Ese 302 lo sirve el BORDE DE CLOUDFLARE. No entró al túnel, no tocó
# traefik, no vio a argocd-server. Y el gate de la fase 35 lo aceptaba:
#
#   gate "edge-responde" ... | grep -qE '200|404|30[12]'
#                                            ^^^^^^^
#
# Un gate llamado «edge-responde» que queda VERDE con el cluster
# entero apagado. Es la enfermedad E en su forma más cara, porque no
# es un gate ausente —esos se ven— sino un gate presente que dice
# PASS. La fase 60 tiene el fallo espejado y menos peligroso: acepta
# `^(200|403)$`, así que bajo Access falla en ROJO y para el init.
#
# ═══ LA SALIDA ═════════════════════════════════════════════════════
#
# NO es dejar de medir el camino público. Ese camino ES el que
# importa: es por donde entra un humano, y es el único que ejercita
# DNS + túnel + traefik + la app de punta a punta. Medirlo por dentro
# (kubectl port-forward) probaría otra cosa.
#
# La salida es el service token que tofu acuñó junto con las
# aplicaciones de Access (`module.access`, outputs
# access_service_token_client_id/_secret), que la fase 25 persiste al
# store como access_st_id / access_st_secret.
#
# Y sobre todo: distinguir «el origen respondió» de «Access
# interceptó». Son dos hechos distintos y hasta hoy daban la misma
# señal.
#
# ═══ A27 ═══════════════════════════════════════════════════════════
#
# El secreto no va por argv (/proc/PID/cmdline es legible). curl no
# soporta `--header @archivo`, pero sí `--config archivo`, que lee las
# cabeceras de disco. El config vive en tmpfs, 600, y se borra.

# _cf_access_config — imprime la ruta de un config de curl con las dos
# cabeceras del service token, o NADA si no hay token en el store.
#
# Devolver vacío no es un error: una instancia sin Access (o una
# corrida anterior a la fase 25) tiene que seguir funcionando por el
# mismo camino, sin ramas especiales.
_cf_access_config() {
    local id sec cfg
    [[ -n "${STATE_SECRETS:-}" ]] || return 0
    [[ -f "$STATE_SECRETS/access_st_id.enc" ]] || return 0
    [[ -f "$STATE_SECRETS/access_st_secret.enc" ]] || return 0
    id="$(sops -d --input-type binary --output-type binary \
        "$STATE_SECRETS/access_st_id.enc" 2>/dev/null)" || return 0
    sec="$(sops -d --input-type binary --output-type binary \
        "$STATE_SECRETS/access_st_secret.enc" 2>/dev/null)" || return 0
    [[ -n "$id" && -n "$sec" ]] || return 0
    cfg="$(mktemp /dev/shm/aegis-cfacc.XXXXXX)"; chmod 600 "$cfg"
    printf 'header = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' \
        "$id" "$sec" > "$cfg"
    printf '%s' "$cfg"
}

# curl_access <args...> — curl que atraviesa Access si hay service
# token. Si no lo hay, corre igual.
curl_access() {
    local cfg rc=0
    cfg="$(_cf_access_config)"
    if [[ -n "$cfg" ]]; then
        curl --config "$cfg" "$@" || rc=$?
        rm -f "$cfg"
    else
        curl "$@" || rc=$?
    fi
    return $rc
}

# edge_origen_responde <url> <regex-de-codigos-aceptables>
#
# Verdadero SOLO si respondió el ORIGEN con un código aceptable. Los
# tres desenlaces se distinguen a propósito, porque son tres causas
# distintas y antes daban una sola señal:
#
#   0  el origen respondió y el código está en el patrón
#   1  VEREDICTO negativo — o Access interceptó (y entonces el origen
#      NO se midió), o el origen contestó algo fuera del patrón
#   2  TRANSPORTE — ni siquiera hubo respuesta (DNS, TLS, timeout)
#
# El discriminante de «Access interceptó» es estructural, no el
# código: un 302 es un 302 lo sirva quien lo sirva. Lo que delata a
# Access es a DÓNDE redirige — *.cloudflareaccess.com. Comparar
# códigos acá sería C15 otra vez: atar el chequeo a un valor que
# cambia cuando la cosa se mueve.
edge_origen_responde() {
    local url="$1" aceptables="$2"
    local cfg out code loc rc=0
    local args=(-sS -m 20 -o /dev/null -w '%{http_code} %{redirect_url}')

    cfg="$(_cf_access_config)"
    [[ -n "$cfg" ]] && args+=(--config "$cfg")
    args+=("$url")
    out="$(curl "${args[@]}" 2>/dev/null)" || rc=$?
    [[ -n "$cfg" ]] && rm -f "$cfg"

    if (( rc != 0 )); then
        printf 'TRANSPORTE: curl rc=%d contra %s — no hubo respuesta\n' \
            "$rc" "$url" >&2
        return 2
    fi

    code="${out%% *}"; loc="${out#* }"
    if [[ "$loc" == *cloudflareaccess.com* ]]; then
        printf 'ACCESS INTERCEPTÓ %s (%s → cloudflareaccess.com): el ORIGEN no se midió.\n' \
            "$url" "$code" >&2
        printf '  falta/no sirve el service token del store (access_st_id, access_st_secret).\n' >&2
        return 1
    fi

    grep -qE "$aceptables" <<<"$code" && return 0
    printf 'el ORIGEN respondió %s contra %s (esperado ~ %s)\n' \
        "$code" "$url" "$aceptables" >&2
    return 1
}
