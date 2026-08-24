# orgs/__ORG__.yaml — el contrato de tu organización.
#
# NACIÓ DE LA PLANTILLA `base` Y LA PLANTILLA YA NO IMPORTA. Desde este
# momento este archivo es la ÚNICA verdad (caminos/design.md §0.1): todo
# lo que la plataforma monta para vos —namespace, cuota, Application de
# ArgoCD, NetworkPolicy, ruteo, job de CI, hostname del borde— se DERIVA
# de estas líneas. Para cambiar algo no se busca a la plantilla: se edita
# ESTE archivo y se re-corre `bin/aegis-org aplicar orgs/__ORG__.yaml`.
# Sos un artesano más, igual que quien lo escribió a mano.
#
# Leelo entero antes de firmar (commitear): es corto a propósito.
version: 1                       # obligatoria; hoy solo existe la 1
organizacion: __ORG__            # inmutable: cambiarla no renombra, crea OTRA
dominio: __DOMINIO__             # el FQDN público; el CNAME del borde sale de acá

# Un PLAN CON NOMBRE, nunca números. Los números viven en plans.yaml y
# se reajustan para todas las organizaciones a la vez. `pequena` es el
# punto de partida sano: subir de plan es editar UNA palabra.
cuota: pequena                   # pequena | mediana | grande

# SIN `almacenamiento:` y SIN `ai:` a propósito: la plantilla `base` es
# la mínima que compila y despliega. El día que los necesites, se
# AGREGAN acá (mirá orgs/ejemplo.yaml, que usa los dos) y se reaplica —
# no hay que volver a ninguna plantilla.

servicios:
  # Un único servicio HTTP. La plataforma espera que escuche en el
  # puerto declarado y lo expone como Service `__ORG__-app` en el 8080;
  # el esqueleto sembrado ya cumple las dos cosas.
  - nombre: app
    tipo: http
    puerto: 8080
    publico: /                   # la raíz del dominio de arriba
    repo: __REPO__               # de acá salen la Application, la deploy
                                 # key y el job de Jenkins — un solo campo,
                                 # tres derivaciones
    # SIN `usa:`. Es una lista blanca de red: lo que no está, la
    # NetworkPolicy lo bloquea. Se declara cuando haga falta
    # (usa: [postgres, bucket, ai]) junto con su sección de arriba.
