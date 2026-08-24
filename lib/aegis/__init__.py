"""aegis — el paquete que comparten los comandos de python.

Existe por una razón medida: en v2 seis comandos cargaban a `aegis-org`
con SourceFileLoader para reusar su validación y sus derivaciones
(docs/cli/inconsistencias.md C1). Cargar un EJECUTABLE por su ruta como
si fuera un módulo tiene tres consecuencias que se pagaron:

  · el check 4 pasaba idéntico con el archivo ausente (A2 del registro):
    el `except ImportError` trataba «no está» como «no aplica»;
  · un `grep` no encuentra esa dependencia — C1/C2 la llaman
    «invisible»: el día que el archivo cambia de lugar, nada avisa;
  · y el ejecutable, al cargarse, corría su preámbulo entero.

Ahora es un paquete de verdad: `from aegis import contrato`. Si el
paquete falta, el import falla y el check se pone rojo, que es lo
correcto — ausencia no es caso legítimo.
"""
