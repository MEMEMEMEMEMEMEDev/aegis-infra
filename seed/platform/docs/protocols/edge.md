# Protocolo: el borde

Cómo un hostname llega a existir en internet, y por qué nadie lo escribe
a mano.

---

## 0. El problema que resuelve

Un hostname público de aegis necesitaba **tres** cosas, en tres lugares:

1. `dominio:` en el contrato de la organización,
2. una entrada en `public_hostnames` de `main.tf`, a mano,
3. que alguien corriera `tofu apply`.

Los pasos 2 y 3 dependían de que una persona se acordara. Y el modo de
fallo es el peor que existe: **si falta, el hostname simplemente no
existe**. No hay error, no hay alarma, no hay nada rojo. El IngressRoute
del cluster está perfecto y nadie llega.

Ya se pagó dos veces:

- `ai.__ROOT_DOMAIN__` estuvo declarado en `main.tf` sin aplicar (tarea
  #35). El gateway corría, su ruta de traefik existía, y el hostname no
  resolvía.
- `blog.__ROOT_DOMAIN__` requirió acordarse de agregarlo el 2026-08-03.

---

## 1. Cómo funciona ahora

```
orgs/veterinaria.yaml           edge.yaml
  dominio: vet.ejemplo.com        plataforma: [aegis, argocd, jenkins, ai]
         │                        dominio_raiz: ejemplo.com
         └────────────┬───────────────────┘
                      ▼
              bin/aegis-org aplicar
                      │
                      ▼
   main.tf: public_hostnames = ["aegis",…,"vet"]   ← GENERADO
                      │
                      │  git push
                      ▼
        el operador corre tofu-apply.sh apply
                      │
                      ▼
              el CNAME existe en Cloudflare
                      │
                      ▼
           job edge-chequeo (diario, sin age key)
                      │
        ┌─────────────┼─────────────┐
       existe       falta      no se pudo
        (ok)        (rojo)      evaluar
                                (amarillo)
```

**Declarar `dominio:` en el contrato es todo lo que hay que hacer.**

---

## 2. La derivación

`bin/aegis-org` calcula la lista como:

```
public_hostnames = edge.yaml:plataforma + [dominio de cada orgs/*.yaml]
```

Reglas:

- **Se leen TODOS los contratos**, no solo el que se está aplicando. La
  lista es de la instancia entera; reescribirla con un contrato solo
  borraría a los demás.
- El contrato declara el **FQDN** (`vet.ejemplo.com`) porque es lo que un
  humano reconoce; tofu quiere la **etiqueta** (`vet`), y el generador
  hace la resta contra `dominio_raiz`.
- Un dominio **fuera de la zona** es un error, no una entrada más: el
  borde solo puede crear CNAMEs dentro de su zona, y otra zona es una
  decisión, no un caso.
- El orden es estable: plataforma en el orden declarado, tenants
  alfabéticos. Sin eso el diff cambia según el sistema de archivos y se
  rompe la idempotencia (regla I1 del protocolo de organizaciones).
- La derivación corre **siempre** al final de `aplicar`, no como un
  comando aparte. Acordarse de correr un comando es exactamente lo que
  falló las dos veces anteriores.

Las puertas de la **plataforma** (`aegis`, `argocd`, `jenkins`, `ai`) no
salen de ningún contrato porque no pertenecen a ninguna organización:
son del sustrato. Viven en `edge.yaml`.

---

## 3. El guard

> **Histórico.** Este guard se diseñó para que el job aplicara solo. Desde
> #46 el job **no aplica** (ver abajo por qué), así que el guard vive en la
> cabeza del operador y no en un `if`. Queda escrito porque el criterio
> sigue valiendo, y porque es lo que hay que mirar antes de tipear `apply`.

El criterio no es "confiar en el pipeline", es **qué puede romper**:

| Plan | Qué significa |
|---|---|
| `0 to add, 0 to change, 0 to destroy` | ya converge, no hay nada que hacer |
| hay cambios, **`0 to destroy`** | aditivo y recuperable — se aplica |
| **cualquier destroy** | **PARÁ Y LEÉ**: borrar un CNAME saca un sitio de internet |
| **muchas altas sobre un entorno convergido** | **no hay state**, no hay trabajo |

La última fila es la más importante y la menos obvia. Un plan lleno de
altas sobre algo que ya debería estar convergido no significa "hay mucho
por hacer": significa que tofu **no está viendo el state**, así que todo
le parece nuevo. Medido el 2026-08-03: el primer build real planificó
"9 to add, 0 to destroy" y el guard del destroy lo dio por bueno. Lo
salvó un error de red, no el diseño.

Detalles que importan:

- Se aplica **el plan guardado** (`plan.bin`), no un plan nuevo. Entre
  el plan y el apply el mundo pudo cambiar; aplicar el binario garantiza
  que lo que se ejecuta es lo que el guard revisó.
- Se usa `-detailed-exitcode` (0 sin cambios, 2 con cambios, 1 error) en
  vez de interpretar el texto.
- Detenerse por un destroy es **UNSTABLE, no FAILURE**: el job hizo bien
  su trabajo. Hay una decisión que le toca a una persona, y eso tiene
  que verse distinto de "se rompió".
- `disableConcurrentBuilds()`: dos applies simultáneos sobre el mismo
  estado son una carrera.

---

## 3.1 El guard del estado, que es el que de verdad importa

Antes del plan, el job verifica que **haya estado**. Va primero porque
es más fuerte que el guard del destroy, y porque el guard del destroy
**no alcanza solo**.

Un plan con altas sobre un entorno que ya debería estar convergido no
significa "hay trabajo": significa que **no hay estado**. Y sin estado
tofu no ve nada de lo que existe, así que todo le parece un alta y
`0 to destroy` pasa con honores mientras se crean recursos duplicados.

Medido el 2026-08-03, en el primer build real del job:

```
Plan: 9 to add, 0 to change, 0 to destroy.
cambios=true destruye=false        ← el guard lo dio por bueno
```

Lo salvó un error de red, no el diseño. Nueve CNAMEs duplicados.

**RESUELTO el 2026-08-04 (#46): el state va CIFRADO Y VERSIONADO, y el
apply del borde es del operador.**

Antes el state vivía solo en la máquina del operador y `*.tfstate`
estaba en `.gitignore`. Eso rompía la identidad del proyecto —arrancar
de cero = recuperarse de un desastre = mudarse de VPS—: un clone virgen
no tiene state, tofu no ve nada de lo que existe, y **todo le parece un
alta**. Intentaría crear de nuevo el túnel y los seis CNAMEs.

Antes de decidir hubo que corregir un dato que este mismo documento
tenía mal. Decía que el state contiene "el ID del túnel y metadatos de
la zona". Se leyó el archivo: contiene **`tunnel_secret` y el token de
Cloudflare EN CLARO**. Eso cambia la pregunta, porque el backend no
custodiaría metadatos sino un secreto de plataforma.

| Dónde | Recuperación | CI puede aplicar | Qué se paga |
|---|---|---|---|
| Solo en la máquina | **rota** | no | el agujero de DR |
| Backend remoto | ok | **sí** | el `tunnel_secret` queda detrás de una credencial nueva |
| **Cifrado en git (elegido)** | ok | no | el apply lo corre el operador |

Se descartó el backend remoto por lo que costaba, no por trabajo: quien
consiga esa credencial levanta su propio `cloudflared` y **recibe el
tráfico de todos los hostnames**. Hoy el peor caso de que se filtre el
token de Cloudflare es una zona de DNS comprometida (§4, D6); eso pasaría
a ser el tráfico entero. Cifrarlo con la age key, en cambio, no agrega
nada nuevo que cuidar: esa llave ya es la raíz de confianza y ya hace
falta para recuperar.

Se descartó el Garage de la propia instancia por la circularidad de
siempre: recuperar el cluster necesita el borde, y el borde necesitaría
el cluster.

**Cómo funciona.** `tofu-apply.sh` descifra `terraform.tfstate.enc.json`
antes de correr tofu y lo vuelve a cifrar después — pero **solo si
cambió**, porque `sops` produce un texto distinto en cada corrida aunque
el contenido sea idéntico, y un diff que no significa nada es un diff que
se deja de leer. El `.tfstate` en claro sigue ignorado; el cifrado no
—`*.tfstate` no lo alcanza porque termina en `.json`, comprobado con
`git check-ignore`.

Verificado moviendo el state en claro fuera del repo y corriendo el
wrapper: descifró los 5 recursos, `state list` devolvió los 9 objetos, y
el `plan` dio **0 to add, 0 to destroy**. Un clone virgen converge sin
duplicar nada.

**Lo que esto cuesta, dicho de frente.** CI no puede aplicar el borde:
descifrar necesita la age key y la age key no entra a CI (§4). El job
`edge-apply` fue reemplazado por `edge-chequeo`, que hace lo que en
realidad motivaba al original —que nadie se entere de que falta un
hostname— sin necesitar ni el state ni la llave: le pregunta a Cloudflare
qué existe y lo compara con lo que derivan los contratos. Ver
`bin/aegis-borde`, que también corre dentro de `bin/aegis-chequeo`.

Ese chequeo **no lee el state**, y no solo porque no podría: el state
dice lo que tofu *cree* que existe, y la única razón de mirar es que
pueden diferir. Un detector que lee el mismo archivo que el aplicador no
detecta nada.

Lo que el chequeo **no** cubre, dicho igual de de frente: mira los CNAME
de la zona, que es exactamente el fallo de #35. No mira las reglas de
ingress del túnel — un CNAME que existe con un túnel que no lo enruta da
404, y eso no se ve desde ahí. Está anotado como límite y no como "ya
está cubierto".

Aplicar el borde es un comando del operador, y con la derivación de §2 no
hay nada que recordar más que correrlo:

```
cd platform/tofu
SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key \
  ./tofu-apply.sh -chdir=envs/cloudflare-tunnel apply
```

Después de aplicar, **commiteá el state recifrado**. Sin ese commit la
próxima recuperación no sabe que lo nuevo existe — el wrapper lo avisa
por stderr en cada corrida que lo modifica.

## 4. La age key no entra a CI

Esto es lo más importante de todo el protocolo.

El job recibe **únicamente el token de Cloudflare**, como credencial de
Jenkins. `tofu-apply.sh` toma el token del entorno si ya está exportado
y no descifra nada — la misma regla que ya valía para `account_id`,
`zone_id` y `root_domain`, aplicada al cuarto valor.

Por qué se puede: **D6 achicó la superficie de tofu a Cloudflare y nada
más.** Ni recursos de Kubernetes, ni GitHub, ni la PKI. Un solo token,
de un tercero, rotable sin ceremonia.

Por qué importa: el peor caso de que ese token se filtre es **una zona
de DNS comprometida**. Con la age key ahí, el peor caso sería *toda la
plataforma* — cada secreto del repo se descifra con ella.

La imagen `aegis-ci-tofu` **no trae sops**, a propósito y para siempre.
Si algún día alguien necesita sops en ese contenedor, la pregunta
correcta es por qué CI está descifrando algo, no cómo agregarle la
herramienta.

---

## 5. Lo que sigue siendo manual, y está bien

- **Un plan con destroy.** Por diseño (§3).
- **Cambiar la zona o la cuenta de Cloudflare.** Eso es una migración,
  no una operación.
- **El primer bootstrap.** La fase 25 del init ya corre
  `tofu apply -auto-approve` sola; este job cubre lo que viene después.

---

## 6. Si sos un agente

- Para publicar un hostname: **editá `dominio:` en el contrato** y
  reaplicá. No toques `main.tf`.
- Si ves `public_hostnames` con un valor que no sale de ningún contrato,
  alguien lo escribió a mano y el próximo `aegis-org aplicar` lo va a
  borrar sin avisar. Llevalo al contrato.
- No agregues sops ni la age key a `aegis-ci-tofu` (§4).
- Un hostname que "no anda" tiene tres capas posibles y conviene
  descartarlas en este orden, porque fallan distinto:
  1. `getent hosts <fqdn>` — si no resuelve, falta el CNAME (tofu).
  2. resuelve pero da 404 — falta el IngressRoute (repo de la app).
  3. resuelve y da 502/503 — el Service o los pods (cluster).
