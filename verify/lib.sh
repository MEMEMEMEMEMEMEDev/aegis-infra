#!/usr/bin/env bash
# verify/lib.sh — lo que todo check tiene a mano.
#
# En v2 el verificador era UN archivo de 3938 renglones, y los cuatro
# modismos de abajo estaban copiados 91, 38, 16 y 11 veces. Cada copia
# era una oportunidad de escribirlo distinto: tres veces el diente
# terminó mordiendo al propio check en vez del artefacto (checks 22, 25,
# 66 y 71 lo cuentan en sus comentarios — «mención ≠ uso»). Es la clase
# que pasó más de dos veces, así que merece mecanismo.
#
# LO QUE UN CHECK PUEDE HACER:
#   check() { ... ; pass "…" }   o   fail "…"     EXACTAMENTE UNA VEZ.
# Un check que no emite veredicto no es «verde»: es el renglón que
# falta, y el runner lo reporta FAIL. Un check que emite dos es un bug
# del verificador y sale con 3. Ninguna de las dos cosas la puede
# tapar el autor del check: las cuenta el runner.
#
# NO hay `set -e` acá y NO hay `pipefail`. La razón está medida (H2
# corrida #15, reproducida 190/200): el patrón dominante es
# `nc archivo | grep -q patrón`, y grep -q sale al PRIMER match → el
# productor recibe SIGPIPE (141) si todavía escribía → con pipefail el
# pipeline «falla» según el scheduler y aparece un rojo que no depende
# del árbol. Los checks cuentan fallos EXPLÍCITOS, no rc de pipelines.

# ── el veredicto ─────────────────────────────────────────────────────
# Se escriben a un archivo y NO a una variable: cada check corre en su
# propio subshell (así una variable de un check no puede filtrarse al
# siguiente — en v2 había 4 de esos acoplamientos), y una variable no
# sobrevive al subshell. El runner lee el archivo y cuenta.
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; printf 'PASS\t%s\n' "$*" >> "$AEGIS_VERDICT_FILE"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; printf 'FAIL\t%s\n' "$*" >> "$AEGIS_VERDICT_FILE"; }

# NO EVALUABLE: el instrumento no llegó al sujeto. NO es verde y NO es
# rojo — es el tercer desenlace (03 §3, rc 2). Un check de perfil que
# no aplica lo DICE con esto en vez de pasar en vacío, que es
# exactamente el silencio que el check 90 de v2 nació para matar.
skip() { printf '\033[1;33mSKIP\033[0m %s\n' "$*"; printf 'SKIP\t%s\n' "$*" >> "$AEGIS_VERDICT_FILE"; }

# ── los cuatro modismos ──────────────────────────────────────────────
# nc: el archivo sin sus comentarios. Un check que busca `|| true` en
# el código no puede confundirse con un comentario que EXPLICA por qué
# no hay `|| true` — la mitad de los falsos rojos de v2 salían de ahí.
nc() { grep -vE '^[[:space:]]*#' "$@"; }

# nc_hits: lo mismo pero sobre salida de `grep -n` (archivo:NN:texto).
nc_hits() { grep -vE ':[0-9]+:[[:space:]]*#'; }

# joincont: junta las continuaciones de línea (\ al final). Sin esto,
# un comando partido en cinco renglones se ve como cinco comandos y
# los guards estructurales se leen mal.
joincont() { sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$@"; }

# body_of FN ARCHIVO: el cuerpo de una función bash, de `fn() {` hasta
# su `}` en columna 0. Es lo que permite preguntar «¿esta función hace
# X?» en vez de «¿el archivo menciona X?» — la distinción que los
# checks 22, 25, 66 y 71 pagaron caro.
body_of() { awk -v fn="$1" 'index($0, fn "()")==1,/^\}/' "$2"; }

# body_nc: el cuerpo, sin comentarios (la combinación más frecuente).
body_nc() { body_of "$1" "$2" | grep -vE '^[[:space:]]*#'; }

# ── dónde está cada cosa ─────────────────────────────────────────────
# Un check NO recalcula rutas: las recibe. (El mismo principio que
# lib/paths.sh para el producto.)
: "${AEGIS_ROOT:?verify/lib.sh requiere AEGIS_ROOT}"
P="$AEGIS_ROOT/semilla/plataforma"   # la SEMILLA — el artefacto que se verifica
FASES="$AEGIS_ROOT/init/phases"
LIBS="$AEGIS_ROOT/lib"
LIBEXEC="$AEGIS_ROOT/libexec"
SEMILLA="$AEGIS_ROOT/semilla"
export P FASES LIBS LIBEXEC SEMILLA

# ── perfil ───────────────────────────────────────────────────────────
# AEGIS_VERIFY_PROFILE lo fija el runner (cloudflare|local). Un check
# que mide algo específico de un perfil pregunta con esto y usa skip()
# para el otro, con el motivo escrito.
perfil() { printf '%s\n' "${AEGIS_VERIFY_PROFILE:-cloudflare}"; }
es_local() { [[ "$(perfil)" == "local" ]]; }
