"""Los tres desenlaces, como contrato de salida.

La doctrina de la casa dice que un comando termina de una de tres
maneras y que confundirlas es la enfermedad, no el síntoma:

    0  HECHO o YA ESTABA     se midió y está bien
    1  MAL / FALTA           se midió y falta o está mal algo
    2  NO SE PUDO EVALUAR    el instrumento no llegó al sujeto
    3  USO INVÁLIDO          flags o argumentos mal

El 2 es el que casi nunca existe en las herramientas y el que más
falta: sin él, «no pude medir» se disfraza de verde («no encontré
fallos») o de rojo («está mal»). Las dos mentiras son caras y la
primera es peor, porque nadie va a investigar un verde.

Y hay un segundo contrato, para cuando el que lee no es una persona:
todo paso emite una línea

    aegis: <paso>  <hecho|ya-estaba|mal|no-evaluable>  [clave=valor ...]

y con --json la narración se reemplaza por un documento. Los
consumidores leen ESO. En v2, `aegis-app` decidía si el webhook se
había creado buscando el texto «webhook creado» en la salida de
`aegis-webhook` (aegis-app:713): un cambio de redacción rompía el
programa. Eso es A3 del registro, y es imposible acá porque no hay
prosa que grepear.
"""
import json
import sys

HECHO = "hecho"
YA_ESTABA = "ya-estaba"
MAL = "mal"
NO_EVALUABLE = "no-evaluable"

# Un solo lugar donde vive la tabla de códigos: la leen este módulo, el
# --help de python (cli.py) y el de bash (lib/common.sh, cli_help). Si
# la tabla se escribiera dos veces, dos veces habría que acordarse.
RC = {HECHO: 0, YA_ESTABA: 0, MAL: 1, NO_EVALUABLE: 2}
RC_USO = 3

def _tabla():
    """La tabla vive en share/codigos-de-salida.txt y la leen los DOS
    lenguajes: este módulo y cli_help() de lib/common.sh. Escrita dos
    veces sería dos veces que acordarse de cambiarla, y la que nadie
    cambia es la que el operador termina leyendo."""
    from . import rutas
    p = rutas.aegis_root() / "share" / "codigos-de-salida.txt"
    if not p.is_file():
        raise RuntimeError(f"falta {p}: el producto está incompleto")
    return p.read_text().rstrip("\n")


TABLA = _tabla()


class Pasos:
    """La lista de pasos de una corrida y su desenlace global.

    El rc global es el PEOR de los pasos, con una regla que no es
    obvia: «no pude evaluar» pesa más que «está mal». Si de diez cosas
    nueve están bien y una no se pudo medir, el desenlace honesto no es
    «una mal»: es «no sé». Un rojo se investiga; un «no sé» disfrazado
    de rojo hace perder el tiempo en el lugar equivocado.
    """

    def __init__(self, json_mode=False):
        self.pasos = []
        self.json_mode = json_mode

    def paso(self, nombre, estado, **datos):
        if estado not in RC:
            raise ValueError(f"estado desconocido: {estado!r}")
        self.pasos.append({"paso": nombre, "estado": estado, **datos})
        if not self.json_mode:
            extra = "".join(f" {k}={v}" for k, v in datos.items())
            print(f"aegis: {nombre}  {estado}{extra}")
        return self

    def hecho(self, nombre, **d):        return self.paso(nombre, HECHO, **d)
    def ya_estaba(self, nombre, **d):    return self.paso(nombre, YA_ESTABA, **d)
    def mal(self, nombre, **d):          return self.paso(nombre, MAL, **d)
    def no_evaluable(self, nombre, **d): return self.paso(nombre, NO_EVALUABLE, **d)

    @property
    def rc(self):
        if not self.pasos:
            # Cero pasos NO es éxito. Un comando que no hizo nada y sale
            # 0 es el silencio con otro nombre.
            return RC[NO_EVALUABLE]
        peor = 0
        for p in self.pasos:
            r = RC[p["estado"]]
            if r == 2:
                return 2
            peor = max(peor, r)
        return peor

    def salir(self):
        if self.json_mode:
            json.dump({"pasos": self.pasos, "rc": self.rc}, sys.stdout, ensure_ascii=False)
            print()
        sys.exit(self.rc)
