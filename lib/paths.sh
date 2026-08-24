#!/usr/bin/env bash
# lib/paths.sh — el ÚNICO lugar donde se decide dónde está cada cosa.
#
# Producto ≠ instancia (02 §1). En v2 eran la misma carpeta y por eso
# nadie tuvo que elegir: el repo del artefacto era también el
# directorio donde vivían platform/, .init-state/ y el store. Cuando la
# instancia avanzó por su cuenta, ese doble papel se volvió la mitad de
# la deuda (docs/cli/inconsistencias.md F1-F4).
#
#   AEGIS_ROOT  el PRODUCTO — este repo, versionado, de solo lectura
#               para la corrida: bin/ libexec/ lib/ init/ verify/
#               semilla/.
#   AEGIS_HOME  la INSTANCIA — mutable, propia de esta máquina:
#               platform/ .init-state/ .state-secrets/ .age-public
#               aegis.conf.
#
# Cada comando de v2 recalculaba esto desde su propio __file__ (seis
# copias de la misma línea: aegis-org:32, aegis-app:96, aegis-edge:45,
# aegis-destroy:26, aegis-backup:21, aegis-restore:15) y eran
# exactamente el tipo de dependencia invisible a un grep que C1/C2 del
# registro nombran. Acá hay una sola.
#
# Este archivo NO depende de nada: lo sourcean tanto common.sh (y con
# ella todo el init) como los comandos que tienen que funcionar con el
# init roto (destroy/backup/restore). El equivalente en python es
# lib/aegis/paths.py, que lee las MISMAS variables de entorno.

: "${AEGIS_ROOT:?paths.sh requiere AEGIS_ROOT (el producto) — lo exporta bin/aegis; un libexec invocado a mano lo resuelve con el preámbulo canónico (V-102)}"

aegis_home() {
    if [[ -n "${AEGIS_HOME:-}" ]]; then printf '%s\n' "$AEGIS_HOME"; return 0; fi
    # Compatibilidad con la forma v2: si el producto tiene un platform/
    # al lado, ESA es la instancia (así está hoy la máquina de casa, y
    # así queda hasta que v3 esté lista — no se migra a la fuerza).
    if [[ -d "$AEGIS_ROOT/platform" ]]; then printf '%s\n' "$AEGIS_ROOT"; return 0; fi
    printf '%s\n' "$HOME/aegis"
}

export AEGIS_HOME="${AEGIS_HOME:-$(aegis_home)}"
: "${PLATFORM_DIR:=$AEGIS_HOME/platform}"
: "${AEGIS_STATE_DIR:=$AEGIS_HOME/.init-state}"
: "${AEGIS_SECRETS_DIR:=$AEGIS_HOME/.state-secrets}"
: "${AEGIS_CONF:=$AEGIS_HOME/aegis.conf}"
export PLATFORM_DIR AEGIS_STATE_DIR AEGIS_SECRETS_DIR AEGIS_CONF
