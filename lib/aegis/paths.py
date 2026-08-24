"""Dónde está cada cosa — la versión python de lib/paths.sh.

Las dos deciden lo mismo y leen las MISMAS variables de entorno, así
que un comando de bash y uno de python puestos uno al lado del otro no
pueden discrepar sobre dónde está la instancia. Si algún día
discrepan, es un bug de una sola clase y se arregla en dos archivos,
no en veinte.

  AEGIS_ROOT   el PRODUCTO: bin/ libexec/ lib/ init/ verify/ semilla/
  AEGIS_HOME   la INSTANCIA: platform/ .init-state/ .state-secrets/
               .age-public aegis.conf

El bug que esto cierra, encontrado el 2026-08-23 al mudar el código:
`aegis-org` calculaba su raíz como `dirname(dirname(__file__))`. Vivía
en <instancia>/platform/bin/, así que eso daba <instancia>/platform y
funcionaba. Al mudarse a <producto>/libexec/ la misma línea siguió
compilando y pasó a apuntar al PRODUCTO — buscando orgs/ y k8s/ donde
no están. Ninguna herramienta lo habría avisado: es la «dependencia
invisible a un grep» de C1/C2, con la fecha puesta.
"""
import os
import pathlib


def aegis_root() -> pathlib.Path:
    """El producto. De la variable si la hay; si no, desde este archivo
    (lib/aegis/paths.py → dos niveles arriba)."""
    v = os.environ.get("AEGIS_ROOT")
    if v:
        return pathlib.Path(v)
    return pathlib.Path(__file__).resolve().parent.parent.parent


def aegis_home() -> pathlib.Path:
    """La instancia. Misma regla que lib/paths.sh, en el mismo orden."""
    v = os.environ.get("AEGIS_HOME")
    if v:
        return pathlib.Path(v)
    raiz = aegis_root()
    # compatibilidad con la forma v2: si el producto tiene un platform/
    # al lado, esa es la instancia (así está hoy la máquina de casa).
    if (raiz / "platform").is_dir():
        return raiz
    return pathlib.Path.home() / "aegis"


def platform_dir() -> pathlib.Path:
    """El checkout vivo del repo de plataforma. Es lo que en v2 se
    llamaba RAIZ dentro de aegis-org."""
    return pathlib.Path(os.environ.get("PLATFORM_DIR") or (aegis_home() / "platform"))


def orgs_dir() -> pathlib.Path:
    return platform_dir() / "orgs"


def state_dir() -> pathlib.Path:
    return pathlib.Path(os.environ.get("AEGIS_STATE_DIR") or (aegis_home() / ".init-state"))


def secrets_dir() -> pathlib.Path:
    return pathlib.Path(os.environ.get("AEGIS_SECRETS_DIR") or (aegis_home() / ".state-secrets"))


def conf() -> pathlib.Path:
    return pathlib.Path(os.environ.get("AEGIS_CONF") or (aegis_home() / "aegis.conf"))


def leer_conf() -> dict:
    """El aegis.conf del wizard, como diccionario.

    Es un archivo de asignaciones de bash (CLAVE=valor). Se lee, no se
    ejecuta: un conf no debería poder correr comandos, y en v2 los
    comandos de python que lo necesitaban lo parseaban cada uno a su
    manera."""
    d = {}
    p = conf()
    if not p.is_file():
        return d
    for linea in p.read_text().splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        k, _, v = linea.partition("=")
        k = k.strip()
        if not k.replace("_", "").isalnum():
            continue
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        d[k] = v
    return d
