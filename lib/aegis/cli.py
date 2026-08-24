"""Lo común de la línea de comandos: el parser y CÓMO se invoca a otro.

`run()` es la regla 5.1 de la doctrina hecha función. El bug que la
justifica está fechado: `aegis-chequeo:766,785` invocaba a
`aegis-borde` y `aegis-webhook` por ruta relativa, y el `case` de
salida no tenía rama para 127. Con el comando ausente, la ronda decía
«sin fallos» — el peor desenlace posible: verde por no haber podido
mirar.
"""
import os
import shutil
import subprocess

from . import rutas
from .desenlaces import TABLA


def libexec() -> str:
    return str(rutas.aegis_root() / "libexec")


def cmd(sub="") -> str:
    """El nombre con el que el operador invocó la CLI.

    Nunca se escribe «aegis» literal en un mensaje: sale de aquí, que
    lo lee de AEGIS_CMD (lo exporta bin/aegis desde argv[0]). Es la
    respuesta de clase a los ~155 strings de la Clase E — no se
    traducen uno por uno, se derivan de uno solo. Check V-103.
    """
    base = os.environ.get("AEGIS_CMD", "aegis")
    return f"{base} {sub}".strip()


def parser(prog, descripcion, protocolo=None, **kw):
    """argparse con el epílogo de la casa: la tabla de códigos (una
    sola, la de desenlaces.py) y dónde está escrito el protocolo."""
    import argparse
    epi = TABLA
    if protocolo:
        epi += f"\n\nel protocolo completo: {protocolo}"
    return argparse.ArgumentParser(
        prog=cmd(prog), description=descripcion, epilog=epi,
        formatter_class=argparse.RawDescriptionHelpFormatter, **kw)


class NoSePudo(Exception):
    """El instrumento no llegó al sujeto. rc 2, jamás 0 y jamás 1."""


def run(comando, *args, capturar=True, entrada=None):
    """Invoca otro comando de aegis y devuelve (rc, stdout, stderr).

    Tres estados que v2 confundía en uno (regla 5.5):
      · el comando NO EXISTE            → NoSePudo («no existe»)
      · existe y no se pudo ejecutar    → NoSePudo («no ejecutable»)
      · existe, corrió y dio un rc      → se devuelve tal cual
    Ninguno de los dos primeros puede terminar en «sin fallos».
    """
    destino = os.path.join(libexec(), f"aegis-{comando}")
    if not os.path.exists(destino):
        raise NoSePudo(f"el comando {cmd(comando)} no existe en {libexec()} "
                       f"— no es que no haya fallos: es que no se pudo mirar")
    if not os.access(destino, os.X_OK):
        raise NoSePudo(f"{destino} existe pero no es ejecutable (chmod +x)")
    r = subprocess.run([destino, *args], capture_output=capturar, text=True,
                       input=entrada)
    # 126/127 desde el propio exec: el intérprete no estaba, o el
    # archivo no era ejecutable. No es un veredicto del comando.
    if r.returncode in (126, 127):
        raise NoSePudo(f"{cmd(comando)} no se pudo ejecutar (rc {r.returncode}: "
                       f"¿falta el intérprete del shebang?)")
    return r.returncode, (r.stdout or ""), (r.stderr or "")


def run_json(comando, *args):
    """Como run(), pero leyendo el CONTRATO en vez de la prosa.

    Agrega --json y devuelve el documento. Es lo que reemplaza a
    `"webhook creado" in r.stdout` (A3): el consumidor lee estados, no
    frases."""
    import json
    rc, out, err = run(comando, *args, "--json")
    try:
        return rc, json.loads(out)
    except (ValueError, json.JSONDecodeError):
        raise NoSePudo(f"{cmd(comando)} --json no devolvió un documento legible "
                       f"(¿todavía no implementa el contrato de salida?)")
