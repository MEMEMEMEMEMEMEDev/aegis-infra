"""Los centinelas y sus productores, en el mismo archivo.

Regla 5.6 de la doctrina, y la clase B del registro con tres casos:

  B1  el banner «GENERADO POR `aegis org`» estaba escrito ocho veces
      como literal, y el GUARDIA que decide si un archivo derivado fue
      editado a mano lo buscaba con un `in` (aegis-org:1165). Cambiar
      la redacción en el productor y no en el guardia no rompe nada
      visible: el guardia deja de reconocer sus propios archivos y las
      ediciones a mano pasan a pisarse en silencio.
  B2  MARCA_JOBS_INI / MARCA_SONDAS_INI, el bloque derivado dentro de
      un values.yaml ajeno: el que escribe y el que vuelve a encontrar
      el bloque tienen que usar exactamente la misma cadena, hasta los
      espacios de sangría (van dentro de un YAML, la sangría es parte
      del centinela).
  B3  el «Retomar:» del orquestador, que un check lee para comprobar
      que el mensaje de retome existe.

La regla es simple: si dos partes del sistema tienen que reconocer la
misma cadena, la cadena vive UNA vez y las dos la importan. El check
V-105 exige que nadie la vuelva a escribir a mano.
"""
import re

# ── el banner de lo derivado ─────────────────────────────────────────
# Se busca por esta subcadena, no por el dibujo completo: el marco de
# la caja puede cambiar de ancho sin que cambie el significado.
FIRMA_GENERADO = "GENERADO POR `aegis org`"

CABECERA = """\
# ╔══════════════════════════════════════════════════════════════════╗
# ║  """ + FIRMA_GENERADO + """ — NO EDITAR A MANO                     ║
# ╚══════════════════════════════════════════════════════════════════╝
# Lo que hay que cambiar es el contrato, y después reaplicar:
#
#     $EDITOR orgs/{org}.yaml
#     aegis org apply orgs/{org}.yaml
#
# contrato: orgs/{org}.yaml
# hash: sha256:{hash}
"""

# El renglón del hash se escribe y se ignora en dos lugares distintos
# (para comparar dos versiones «salvo el hash»). Un prefijo, una vez.
PREFIJO_HASH = "# hash: sha256:"


def es_generado(texto: str) -> bool:
    """¿Este archivo lo escribió el generador? La pregunta que hace el
    guardia antes de pisar nada."""
    return FIRMA_GENERADO in texto


def sin_hash(texto: str) -> str:
    """El texto sin su renglón de hash, para comparar contenido."""
    return "\n".join(l for l in texto.splitlines() if not l.startswith(PREFIJO_HASH))


# ── los bloques derivados dentro de archivos ajenos ──────────────────
# La sangría es parte del centinela: estos bloques viven DENTRO de un
# YAML (values.yaml de jenkins y de vmagent), y con otra sangría el
# archivo deja de parsear.
MARCA_JOBS_INI = "          # --- DERIVADO por aegis-org (jobs de tenant): no editar a mano ---"
MARCA_JOBS_FIN = "          # --- FIN DERIVADO ---"
MARCA_SONDAS_INI = "    # --- DERIVADO por aegis-org (sondas de tenant): no editar a mano ---"
MARCA_SONDAS_FIN = "    # --- FIN DERIVADO ---"

PATRON_BLOQUE_JOBS = re.compile(
    re.escape(MARCA_JOBS_INI) + r"\n(?:.*\n)*?" + re.escape(MARCA_JOBS_FIN))
PATRON_BLOQUE_SONDAS = re.compile(
    re.escape(MARCA_SONDAS_INI) + r"\n(?:.*\n)*?" + re.escape(MARCA_SONDAS_FIN))

# ── el centinela del orquestador ─────────────────────────────────────
# Lo imprime aegis-init al fallar una fase y lo busca el check 73. La
# forma importa: tiene que poder pegarse desde cualquier directorio.
PREFIJO_RETOME = "Retomar:"


# El marco solo, sin el cuerpo: lo usan los seis generadores que
# escriben archivos derivados que NO son de una organización (tenants,
# appprojects, secret-generators, el cableado de garage…). En v2 cada
# uno lo llevaba escrito a mano: seis copias de tres renglones, y el
# guardia buscando una subcadena en el medio.
MARCO = [
    "# ╔══════════════════════════════════════════════════════════════════╗",
    "# ║  " + FIRMA_GENERADO + " — NO EDITAR A MANO                     ║",
    "# ╚══════════════════════════════════════════════════════════════════╝",
]
BANNER = "\n".join(MARCO)
