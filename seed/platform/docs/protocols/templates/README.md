# Plantillas para el repo de una app

Lo que hay acá es el punto de partida de una app que consume la
plataforma. Tres archivos, y van juntos:

| archivo | va en el repo de la app como |
|---|---|
| `Jenkinsfile.app` | `Jenkinsfile` |
| `write-digest.mjs` | `ci/write-digest.mjs` |
| `kustomization.overlay.yaml` | `k8s/overlays/dev/kustomization.yaml` |

Cambiá **solo** lo marcado `CHANGEME`. El resto es contrato con la
plataforma —pines, secretos, límites—; si algo de eso no te sirve, el
cambio va en el repo de la plataforma, no en tu app.

## Hay DOS referencias, y copiar la equivocada duele

**Esta plantilla** es para la **primera app de una instancia recién
nacida**. Tolera que la infraestructura todavía no exista: durante las
fases 50-70 del init no hay trivy-server ni clave de cosign, así que
`scan` y `sign` se **saltan con WARN** en vez de romper el build.

**`ejemplo-app`** es la **referencia viva**: una app real sobre una
instancia que ya funciona. No tolera nada — si el trivy-server no
responde, el build se cae. Y corre en cada push, así que no se pudre.

Cuál copiar:

- Instancia nueva, todavía arrancando → **esta plantilla**.
- App nueva sobre una instancia que ya anda → **`ejemplo-app`**, que
  además muestra el camino completo con base de datos, bucket y dos
  imágenes en el mismo repo.

**No mezcles.** Traer la tolerancia de bootstrap a una app real es meter
a mano un pipeline que no distingue *"escaneado y limpio"* de *"no se
escaneó"*. Eso es exactamente la clase de señal ciega que esta
plataforma existe para eliminar. Una vez que la instancia está en pie,
un trivy caído **tiene** que romper el build.

## Lo que la plantilla NO puede darte

La tolerancia de bootstrap es lo único que esta plantilla tiene y
`ejemplo-app` no. Todo lo demás —la etapa `desplegar`, el despliegue por
digest, `safe.directory`, la guarda de rama— está en las dos, y lo que
esté mejor explicado en `ejemplo-app` es la fuente.

## Lo que hace falta que exista antes

En el namespace `jenkins-system` (los crea el init, ver
`registry-credentials.md`):

- `Secret regcred-internal` — dockerconfigjson del registry
- `Secret aegis-ca-trust` — `ca.crt` del CA interno
- `Secret cosign-signing-key` — `cosign.key` + `cosign.password`

Y una credencial `github-token` en Jenkins con permiso de **escritura**
sobre el repo de la app: la etapa `desplegar` commitea el digest.

El ruteo **no** hace falta declararlo. Desde #54 lo deriva la plataforma
del contrato de la organización (`orgs/<org>.yaml`), y el repo de la app
no puede escribirlo aunque quiera. Lo que sí tenés que respetar es la
convención de nombres: el servicio `X` del contrato se expone como
Service `<org>-X` en el puerto **8080**.

## Historia, porque explica la forma

Hasta el 2026-08-06 esta plantilla **no tenía etapa de despliegue**.
Quien la copiaba obtenía un pipeline que construía, escaneaba, publicaba
y firmaba la imagen — y después no desplegaba nada. Terminaba en verde,
porque hacía todo lo que decía hacer: lo que faltaba no estaba roto,
estaba **ausente**, y ningún chequeo mira lo que no existe.

El canario la copió tal cual y estuvo así meses sin que nadie lo notara.

La lección quedó horneada en los comentarios del `Jenkinsfile.app`, y
vale más que el archivo: **una plantilla que nadie ejercita se pudre**.
Por eso la referencia para el caso normal es `ejemplo-app`, que corre de
verdad en cada push, y esta plantilla queda acotada al único caso que
`ejemplo-app` no puede cubrir.
