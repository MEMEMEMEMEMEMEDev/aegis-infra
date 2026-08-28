# aegis-infra

**Una plataforma GitOps autohospedada que se instala sola y después lo demuestra.**

Read this in English: [README.en.md](README.en.md)

Pones una máquina Linux y una cuenta de GitHub. `aegis init` las
convierte en una plataforma Kubernetes donde cada `git push` se
construye en un pod sin privilegios, se escanea, se firma por digest,
se despliega por GitOps y se expone a internet con TLS. Una imagen sin
firma se rechaza en la admisión, no se descubre después.

Montar algo así exige juntar una docena de piezas y acordar cómo se
hablan entre sí; ese acuerdo suele vivir en la cabeza de una persona y
en una máquina concreta. aegis-infra lo convierte en un artefacto: un
instalador por fases que registra una puerta medida por cada paso, un
verificador estático sin clúster y una ronda de operación que mide el
clúster vivo contra lo declarado.

> **Estado: avance técnico (*technical preview*).** Esta es la
> versión para desarrolladores y equipos de plataforma. Está medida, no
> pulida: la instalación completa corrió de extremo a extremo en una
> máquina que no era la del autor (ver [dónde se corrió](#dónde-se-corrió-y-con-qué-resultado)),
> y cada afirmación de este documento sale de una puerta o de un check
> que se puede volver a ejecutar. Una capa más amigable, para quien no
> quiere leer un Jenkinsfile y para desarrolladores junior, es lo
> próximo que se construye encima de esta. Todavía no está.

---

## Qué obtienes

- **Una plataforma desde un comando.** `aegis init` corre quince fases
  idempotentes: host, raíz de confianza (age/sops), el repo GitOps que
  posee, k3s, el borde, ArgoCD, el registro interno y su PKI, Jenkins,
  webhooks, un despliegue canario, la cadena de suministro y la
  observabilidad. Reejecutar converge: lo hecho se salta, lo que falta
  se hace.
- **Una cadena de suministro con dientes.** Construir con kaniko,
  escanear con Trivy (un HIGH/CRITICAL corregible es un build rojo),
  firmar con cosign por digest, admitir con Kyverno en Enforce. Las
  imágenes de la propia plataforma salen de un espejo fijado por
  versión; sus imágenes base se construyen en la propia instancia y se
  reescanean a diario contra la base de vulnerabilidades del día.
- **Tenants desde un contrato.** Un YAML por organización
  (`orgs/<nombre>.yaml`; un *tenant* es una organización con su
  namespace) es la única verdad: namespaces, cuotas, NetworkPolicies,
  RBAC, jobs de Jenkins, apps de ArgoCD, hostnames, secretos y
  respaldos se *derivan* de él. `aegis org apply` vuelve a
  derivar; nada se escribe dos veces a mano.
- **Observabilidad que se vigila a sí misma.** VictoriaMetrics, vmalert,
  Grafana, sondas blackbox y una bitácora de eventos, con alertas al
  teléfono vía ntfy. Y una regla: toda métrica que lee una alerta la
  produce algo, para que un exporter roto no pueda quedarse callado.
- **Recuperación ensayada.** `aegis state backup` (el estado de la
  máquina), `aegis data backup` (los datos de los tenants),
  `aegis rotate` (toda credencial que genera el init se puede rotar),
  `aegis destroy` (deshacerlo todo) y un documento de ensayo para
  hacerlo en una máquina que no es la tuya.
- **Un verificador.** `aegis verify` corre 136 checks estáticos sobre
  el artefacto sin necesitar un clúster. Cada check tiene un *diente*:
  una mutación que rompe lo que el check protege, para probar que el
  check muerde. `aegis check` es la misma idea contra un clúster vivo.

## Dónde se corrió y con qué resultado

Medido, no recordado. Las fechas son los días en que ocurrieron las corridas.

| dónde | qué | resultado |
|---|---|---|
| Un VPS alquilado: 4 CPU / 16 GB, Ubuntu, nada más que ssh; una **cuenta de GitHub nueva**; **sin dominio** (`EDGE=local`) | `aegis init` desde cero (2026-08-27) | 15/15 fases, 174 puertas pasadas, 20 registradas como *no evaluables* (necesitan un borde público) |
| mismo host | dos tenants dados de alta desde sus contratos, sus datos restaurados desde respaldos, catálogo servido por HTTPS | hecho; 12 productos y 4 pedidos, fotos y usuarios donde el respaldo decía |
| mismo host | la cadena de suministro de extremo a extremo | canario firmado admitido; imagen sin firma rechazada citando la política; espejo (`mirror-images`) y vigilancia diaria (`image-watch`) con cero CVEs corregibles |
| mismo host | `aegis state backup` → `aegis state restore` en un segundo directorio de instancia | ida y vuelta verificada |
| mismo host | `aegis verify --profile both` sobre la instancia | todo pasa, en ambos perfiles |
| mismo host, **sucio** | `aegis destroy --k3s` y un segundo `aegis init` sobre los restos (2026-08-27) | 15/15 fases; las tres cosas que deja una instancia previa (una política de admisión heredada, una CA obsoleta, un registro de imágenes que ya no existe) ahora las detecta y repara el propio init |
| la máquina del autor | el linaje del que viene esta reconstrucción sirve los sitios públicos del autor detrás de un borde de Cloudflare desde hace alrededor de un año | en uso diario |

Esa primera corrida en máquina ajena necesitó catorce reanudaciones
(`aegis init --from`) y encontró unos treinta defectos que los checks
estáticos no podían ver. No eran errores del código: eran errores de la
*distancia* entre el producto y su primera instancia real. Están todos
cerrados, cada uno con su check, y sus clases tienen nombre en
`seed/platform/docs/failure-modes.md` (enfermedades E a H). El ensayo
está escrito para poder repetirse: `docs/journeys/foreign-instance.md`.

**Lo que todavía no se ha medido:** el perfil de borde `cloudflare` de
*esta* reconstrucción en una máquina ajena. El linaje lo corre en la
máquina del autor; bajo `EDGE=local` las puertas de ese perfil quedan
registradas como no evaluables.

## Cómo funciona por dentro

### Las quince fases

`aegis init --list` las imprime con su estado. Cada una deja un
marcador y registra sus puertas en `.init-state/gates.jsonl` de la
instancia; una fase pasada no se repite salvo que `--from` o `--only`
lo pidan.

| fase | qué hace |
|---|---|
| `00-preflight` | Comprueba las precondiciones y muestra los límites conocidos. Lanza el asistente de configuración si no hay `aegis.conf`. Si falta algo, aborta aquí, no a mitad del clúster. |
| `05-host` | Instala en el host el userland fijado por versión (tofu, sops, age, kubectl, helm, cosign, direnv, jq, git, openssl; `gh` con pin `apt`: basta que esté presente, sin comparar versión; lo que el init exige es la sesión autenticada), leyendo los pins de `group_vars/all.yml`, con espera del lock de apt. |
| `10-age-ceremony` | Genera la clave age (la raíz de confianza), la valida cifrando y descifrando de verdad, deja respaldos y renderiza `.sops.yaml`. Es la única fase que muestra un secreto al operador. |
| `12-workrepos` | Crea y siembra en GitHub, vía `gh`, los dos repos propios del init (plataforma y canario), marcados con un topic. En reejecución los reutiliza; si el repo existe sin la marca, pregunta al operador antes de marcarlo (y se niega sin terminal). |
| `15-third-parties` | Credenciales de terceros sin navegador: claves de despliegue (*deploy keys*), HMAC de webhooks y credencial de CI desde la sesión de `gh`. Bajo `EDGE=cloudflare` acuña además tokens acotados de Cloudflare. |
| `20-k3s` | Prepara el kernel del host e instala k3s fijado por versión con los playbooks de Ansible del repo de plataforma. |
| `25-edge-tofu` | Levanta el borde. Con `cloudflare`: túnel, DNS y Access vía OpenTofu. Con `local`: un puente de systemd en el host que entrega 80/443 a Traefik. |
| `30-argocd` | Instala ArgoCD con helm (la única instalación imperativa) y crea con kubectl los Secrets de arranque, entre ellos la clave age para KSOPS. |
| `35-gitops` | Entrega el control a GitOps: AppProjects, App raíz y sincronizaciones en orden (cert-manager, PKI, Traefik, cloudflared…). |
| `40-registry-pki` | Registro interno de imágenes con PKI propia y TLS desde el primer día; credenciales derivadas de un único origen e instalación de la CA en el host. |
| `50-jenkins` | Jenkins con jobs-as-code desde el nacimiento y secretos antes del chart. Cierra con la imagen de herramientas de CI construida y publicada. |
| `60-webhook` | Comprueba de extremo a extremo que un push llega a Jenkins, con una puerta por eslabón (borde, hook, entrega, build existe, build verde). Bajo `EDGE=local` los eslabones de hook y entrega quedan como no evaluables; el build se mide por sondeo. |
| `70-deploy-auto` | Despliegue automático del tenant canario: el pipeline escribe el digest en el overlay y ArgoCD despliega; el anti-bucle (un commit solo de k8s no dispara build) se prueba antes de que se escriba nada. |
| `80-supply-chain` | Servidor Trivy, clave cosign y política Kyverno en Enforce, activada al final, después de que exista la primera imagen firmada. |
| `85-observability` | Sobre todo lo que ya existe: VictoriaMetrics, vmalert, Grafana, sondas y bitácora de eventos, con un latido que llega al `topic` de ntfy. |

El orden no es cosmético. La política de admisión se activa cuando ya
hay una imagen firmada que admitir; la observabilidad se instala al
final porque mide lo que ya existe; los secretos entran antes que los
charts que los consumen.

### La cadena de suministro, paso a paso

1. Un push llega a Jenkins por webhook (o por sondeo bajo `EDGE=local`).
2. kaniko construye la imagen en un pod sin privilegios; el
   Containerfile de la plantilla corre sin root bajo PSS restricted.
3. Trivy escanea con `--exit-code 1 --severity CRITICAL,HIGH
   --ignore-unfixed`: un hallazgo corregible de esa severidad detiene
   el build.
4. cosign firma por digest, nunca por tag, con la clave de la
   instancia.
5. El pipeline que construyó la imagen escribe su digest en el overlay
   de kustomize (`ci/write-digest.mjs`) y hace commit; ArgoCD
   despliega.
6. Kyverno (`require-aegis-signature`, en Enforce, con `mutateDigest`)
   rechaza en la admisión cualquier imagen sin firma válida.

Las imágenes de la plataforma siguen la misma disciplina. El job
`mirror-images` fija por versión lo que se trae de fuera; `ci-images`
construye la imagen de herramientas de CI; `base-images` fabrica las
bases propias; `image-watch` las vuelve a escanear a diario (cron
`H 6 * * *`). `aegis ci build` dispara los cuatro en ese orden y espera
a cada uno; `aegis ci digests` lista `imagen@digest` para que un humano
lo lea antes de subir un `FROM` a mano.

### Las ideas que ordenan todo lo demás

- **Producto e instancia son dos cosas.** El producto es este
  repositorio, de solo lectura durante una corrida. La instancia es el
  estado vivo de una máquina: el repo GitOps, los marcadores de fase,
  el almacén cifrado, la configuración. Un solo archivo decide dónde
  vive cada cosa, en bash y en python, para que dos comandos no puedan
  discrepar.
- **El contrato es la única verdad.** Las plantillas generan
  contratos; todo lo demás se deriva de ellos, y la derivación es
  idempotente (un bloque marcado, reescrito entero, cada vez).
- **Converger, no ejecutar.** Todo comando que se reejecuta con el
  trabajo ya hecho termina en *nada que hacer*.
- **Cuatro salidas, siempre.** `0` hecho o ya estaba · `1` mal o
  falta · `2` no se pudo evaluar · `3` uso inválido. *No se pudo
  evaluar* es una respuesta de primera clase: un instrumento que nunca
  llegó a su sujeto no dice que el sujeto esté bien.
- **El silencio nunca es éxito.** Una puerta sin sujeto se registra
  como tal; un build que nunca apareció es un fallo; un asistente de
  configuración que no pudo escribir el archivo muere en vez de seguir.
- **Un check que no muerde no existe.** Cada check viene con la
  mutación que demuestra que falla cuando debe (`aegis verify --teeth`).
- **El producto no nombra máquinas ni personas.** La semilla lleva
  marcadores de posición, nunca valores; dos checks mantienen fuera
  direcciones e identidades, para que lo que se instala aquí se instale
  en cualquier parte.

## Requisitos

- **Un host Linux con `sudo`.** Ubuntu es lo que se ha corrido; el
  playbook de Ansible que prepara el host exige Ubuntu 24.04 o superior
  con systemd. El preflight configura `sudo` sin contraseña, instala
  con `apt` tmux, python3-yaml y jq (y `gh` si falta), y exige curl,
  git y python3 ya presentes. Conviene correr el init dentro de tmux
  (el preflight lo instala): la corrida es larga y una sesión ssh caída
  la mataría.
- **4 CPU y 8 GB de RAM alcanzan.** El preflight avisa por debajo de
  7 GB: Jenkins, Kyverno y Trivy quedan justos. Con menos de 25 GB
  libres en `/` falla. `/dev/shm` escribible, para las ceremonias de
  age y cosign.
- **Salida a internet por IPv4.** El preflight sondea seis destinos,
  con cualquier perfil: github.com, api.github.com, api.cloudflare.com,
  get.k3s.io, dl.k8s.io y Docker Hub. El espejo puede tirar de otros
  registros; esos no se sondean.
- **Reloj en hora e IPv6 apagado.** Desfase de reloj de 120 s o menos
  contra GitHub e IPv6 desactivado de forma persistente; el preflight
  hace ambas cosas.
- **`gh` autenticado** por el operador con `gh auth login` (el
  preflight lo instala si falta); el preflight dice qué permisos
  (*scopes*) pide. El init **crea y posee** los dos repos que necesita
  (plataforma y canario); deben ser nombres nuevos.
- **Identidad git global** (`user.name` y `user.email`); el preflight
  la pregunta si hay terminal.
- **Un host sin restos de otra instancia.** El init avisa si existen.
  Sobre restos también funciona (está medido): lee la fila **sucio** de
  la tabla.
- **Opcional: una cuenta de Cloudflare con una zona**, para
  `EDGE=cloudflare` (hostnames públicos, un túnel, TLS de un emisor
  ACME). Sin ella, `EDGE=local` te da la misma plataforma sobre nombres
  que resuelven al host (vía sslip.io), con TLS de la CA propia de la
  instancia.

## Empezar

Clona el producto, deja la máquina lista y lanza el init dentro de tmux:

```bash
git clone <este repositorio> aegis-infra
cd aegis-infra
./bin/aegis preflight      # deja la máquina como la necesita el init, o dice por qué no
gh auth login              # si el preflight lo pidió; después, preflight otra vez
tmux new -s aegis          # el init es largo; una sesión ssh caída lo mataría
./bin/aegis init           # el asistente de configuración y, después, quince fases
./bin/aegis check          # la ronda rutinaria contra el clúster vivo
```

En adelante este documento escribe `aegis` a secas; es `./bin/aegis`
desde el checkout del producto.

### Lo que pregunta el asistente de configuración

`aegis init` pregunta pocas cosas:

- El perfil de borde (`EDGE`): `cloudflare`, con zona propia, túnel y
  Access; o `local`, con un puente en el host, nombres vía sslip.io y
  TLS de la CA interna.
- El dueño de GitHub; se infiere de la sesión de `gh`.
- Los nombres de los dos repos que el init crea y posee; por defecto
  `aegis-platform` y `aegis-canary`, y deben ser nuevos.
- El dominio raíz; en `local` propone uno de sslip.io.
- Un correo de contacto para certificados; se infiere de `git config`.
- El contexto de kubectl que exige antes de tocar el clúster.
- El ClusterIP del registro interno de imágenes.
- El espacio de trabajo para direnv.

Solo bajo `cloudflare` pide el ID de cuenta y el ID de zona de
Cloudflare; solo bajo `local`, dónde escucha el puente (por defecto
loopback). Muestra un resumen, pide confirmación y escribe `aegis.conf`
de forma atómica. Con `--non-interactive` y sin `aegis.conf` se niega
a correr.

### Si se cae

La fase `10-age-ceremony` es la única que te muestra un secreto: la
clave age es la raíz de confianza de la instancia; guárdala donde el
init te indica. Cuando una fase falla, el init se detiene en ella y
deja su puerta registrada. Arregla la causa y reanuda:

```bash
aegis init --from 30      # reanuda desde la fase 30 (las anteriores ya pasaron)
aegis init --only 60      # repite una sola fase
aegis init --check        # mide sin cambiar nada
aegis init --list         # qué fases hay y cuáles pasaron
aegis init-log            # lo mismo que init, dejando un dosier completo de la corrida
```

`aegis init-log` imprime la ruta del dosier *antes* de empezar, para
que la conozcas aunque la corrida muera. La caja negra es
`.init-state/gates.jsonl`; `docs/OPERATE.md` explica por dónde empezar
a diagnosticar.

Para empezar de cero sobre el mismo host:

```bash
aegis destroy             # sin --yes es un dry-run: dice qué quitaría
aegis destroy --yes --k3s # quita el borde, el puente y el clúster
aegis init --reset-state  # olvida todas las puertas y vuelve a empezar
```

`aegis destroy` no borra los repos de GitHub: llevan el topic marcador
del init y una reejecución los reutiliza.

## Dar de alta una aplicación

Hay una plantilla, `base`: un servicio HTTP mínimo en Go sin
dependencias externas, con su contrato, un `Containerfile` que corre sin root
(PSS restricted), overlays de kustomize y el script que escribe el
digest. El `Jenkinsfile` no vive en la plantilla: `aegis org` lo
instancia desde la plantilla canónica.

```bash
aegis app new shop --template base   # escribe contrato, esqueleto, derivaciones y secretos; no toca el mundo
git diff                             # lee lo que derivó
git add -A && git commit -m "org: shop" && git push
aegis sync root                      # ArgoCD recoge la organización nueva
aegis app apply shop                 # crea el repo, la clave de despliegue y el webhook en GitHub
```

`aegis app apply --check` muestra lo que haría sin tocar nada. Desde
el primer push al repo de la app, la plataforma la construye, escanea,
firma, despliega y expone. Bajo `EDGE=local` el webhook queda como no
evaluable y Jenkins sondea el repo en su lugar.

La plantilla desaparece una vez instanciada: nada de lo generado
recuerda de dónde vino. Desde ahí el contrato y el repo son tuyos y
los editas a mano (sin `--template`, `aegis app new` solo rederiva).
Un contrato declara, entre otras cosas, servicios (Postgres, una base
de datos por organización), un bucket de Garage y las rutas públicas.
Para cambiar la organización, editas el contrato y vuelves a derivar:

```bash
$EDITOR orgs/shop.yaml               # añadir postgres, bucket, otro servicio…
aegis org plan orgs/shop.yaml        # qué cambiaría, sin escribir
aegis org apply orgs/shop.yaml       # escribe los manifiestos
aegis secret create orgs/shop.yaml   # si aparecieron secretos nuevos
```

`seed/platform/docs/platform-for-developers.md` es la página que se
entrega al equipo que va a hacer push: el ciclo de vida de un push y
las reglas que lo rechazan.

## Los comandos

`aegis --help` imprime el menú; `aegis <cmd> --help`, el detalle de
cada uno. Todos, salvo `aegis verify`, devuelven los mismos cuatro
códigos de salida; `verify` usa 0, 1 y 3, donde 3 es un defecto del
propio verificador.

### setup

| comando | qué hace |
|---|---|
| `aegis preflight` | Deja la máquina en el estado que el init necesita (sudo sin contraseña, IPv6 apagado, DNS, reloj, paquetes, identidad git). Sin argumentos: actúa y repara. |
| `aegis init` | El orquestador: levanta la plataforma fase por fase y registra una puerta por paso. Reejecutar converge. `--from N`, `--only N`, `--check`, `--configure`, `--list`, `--reset-state`, `--non-interactive`. |
| `aegis init-log` | Ejecuta `aegis init` bajo `script`, dejando un dosier completo de la corrida. Acepta los mismos flags. |
| `aegis verify` | Verificación estática del artefacto, sin clúster: los checks de `verify/checks/`. `--profile cloudflare\|local\|both`, `--only NNN`, `--teeth [NNN]` (prueba que cada check muerde), `--harness` (los arneses funcionales), `--with-charts`, `--list`. |
| `aegis destroy` | Deshace la huella del init en el borde y en este host; con `--k3s` también el clúster; con `--purge-secrets`, el almacén de la instancia. Sin `--yes` es un *dry-run*. No borra los repos de GitHub. |

### apps

| comando | qué hace |
|---|---|
| `aegis app new` / `apply` | `new` escribe el alta entera en archivos (contrato desde una plantilla con `--template`, esqueleto, derivaciones, secretos) sin tocar el mundo; `apply` ejecuta los pasos de GitHub de cada contrato: repo, esqueleto, clave de despliegue, webhook (`--check` para verlo sin tocar nada). |
| `aegis org plan` / `apply` / `validate` / `edge` / `routes` / `plan-delete` / `delete` / `migrate` | `plan` muestra qué cambiaría; `apply` escribe los manifiestos; `validate` solo valida el contrato; `edge` deriva los hostnames públicos de todos los contratos; `routes` deriva el ConfigMap de rutas de IA (`ai-ruteo`); `plan-delete` muestra qué borraría; `delete` borra del repo y *dice* qué retirar del clúster; `migrate` lleva un contrato a una versión nueva. |
| `aegis secret create` / `rotate` / `move` | Crea los secretos cifrados que faltan (nunca regenera), reemplaza el material, o copia un secreto a otro namespace (`move` necesita la clave age). |

### operate

| comando | qué hace |
|---|---|
| `aegis check` | La ronda rutinaria. Sin argumentos y sin escribir nada: mide el clúster vivo contra lo declarado (firma en Enforce, respaldos por organización, desincronías). |
| `aegis sync` | Dispara un sync de ArgoCD de las apps nombradas sin pasar `syncOptions`; `--drifted` sincroniza todo lo que no esté Synced. |

`aegis ai` (el control del operador sobre el sustrato de IA) también
está en este grupo; queda fuera de este documento.

### infra

| comando | qué hace |
|---|---|
| `aegis ci build` / `digests` | `build` dispara los jobs de imágenes de la plataforma en orden (`mirror-images` → `ci-images` → `base-images` → `image-watch`) y espera a cada uno; `digests` lista `imagen@digest` de lo que guarda el registro interno. |
| `aegis edge check` | Compara los hostnames vivos con los derivados de los contratos. |
| `aegis registry check` / `rotate` | `check` verifica que la credencial del registro interno esté alineada en sus diez destinos; `rotate` la genera de nuevo y reescribe los diez. |
| `aegis rotate list` / `check` / `run` / `continue` | El protocolo de rotación hecho ejecutable: inventario, comprobar si una credencial funciona sin rotarla, rotar (con el radio de impacto a la vista) y reanudar un lote interrumpido. |
| `aegis webhook check` / `apply` | Mide que todo repo con job tenga webhook; crea los que faltan resincronizando el HMAC. |

### backup

| comando | qué hace |
|---|---|
| `aegis data backup` / `list` / `restore` | Los DATOS de los tenants: un bundle por organización. `list` mira dentro sin restaurar; `restore` exige `--org` y, si la credencial rotó desde la captura, `--force`. |
| `aegis state backup` / `restore` | Los tres estados que viven solo en esta máquina y que ningún git guarda: el almacén cifrado, los marcadores de fase y el tfstate del borde. Perder cualquiera obliga a rehacer la instalación a mano. |

`state` es la máquina (lo que hace falta para reconstruir la
instalación); `data` son los tenants (lo que hace falta para
reconstruir sus aplicaciones y sus datos). El respaldo de uno no
restaura el otro.

## Qué hay dentro

```
bin/          el despachador (aegis <comando>)
libexec/      un archivo por comando
lib/          los helpers compartidos, bash y python
init/         el orquestador y sus quince fases
verify/       los checks, sus dientes, los arneses
seed/         lo que se distribuye: el repo de plataforma, el canario, las plantillas
share/        los códigos de salida y las unidades de systemd
docs/         AGENTS.md (cómo cambiar esto), OPERATE.md (cómo operarlo),
              el glosario, los journeys de diseño
```

Lo que corre en el clúster: k3s v1.35.4+k3s1 (sin Traefik ni servicelb
de fábrica), instalado por Ansible; ArgoCD con KSOPS; Jenkins con
jobs-as-code y kaniko; Trivy, cosign y Kyverno; Traefik y cert-manager
con CA interna; cloudflared solo bajo `EDGE=cloudflare`;
un registro interno de imágenes con TLS de la PKI propia; Garage (S3) y
Postgres 17 como tipos de servicio, un bucket y una base de datos por
organización; VictoriaMetrics, VictoriaLogs, Grafana, Vector,
blackbox-exporter, Alertmanager y ntfy; NetworkPolicies por tenant
(default-deny con egress DNS) y PSS restricted en el canario y en cada
namespace de tenant. En el host: sops 3.9.4 y age 1.2.1 para el
almacén cifrado, OpenTofu 1.12.3 solo para el borde de Cloudflare
(túnel, DNS y Access). Los charts se fijan por versión en el repo de
plataforma; el userland, en `group_vars/all.yml`.

Por dónde empezar a leer:

- `docs/AGENTS.md`, si vas a cambiar el producto: el método, las reglas
  nacidas de incidentes reales, dónde vive cada cosa.
- `docs/OPERATE.md`, si vas a operar una instancia: estado esperado,
  diagnóstico, qué desincronías son benignas, herramientas de
  recuperación.
- `docs/glossary.md` es el vocabulario; `aegis verify` lo hace cumplir.
- `docs/journeys/foreign-instance.md` es el ensayo en máquina ajena,
  escrito para repetirse.
- `seed/platform/docs/failure-modes.md` cataloga las clases de fallo
  (enfermedades A a H) con firma y arreglo.
- `seed/platform/docs/platform-for-developers.md` es lo que lee el
  equipo que hace push.

## Lo que no está

Dicho claro, porque los checks lo dirían igual.

- El perfil `cloudflare` de esta reconstrucción no se ha corrido en una
  máquina ajena.
- Un arreglo en la semilla no llega a una instancia ya sembrada;
  resembrar una instancia viva es manual.
- `aegis data restore` restaura la base de datos, no los objetos del
  bucket (lo dice al correr). Tras `--force`, el rol de la base de
  datos se realinea a mano. Y restaurar entre instancias no es automático: el
  bundle viene cifrado a la clave age de la instancia que lo hizo, hay
  que recifrarlo a la clave de la nueva, y `restore` exige `--force`
  porque detecta que la credencial de la base de datos cambió.
- Una sola plantilla de aplicación (`base`). Una plantilla de sitio
  estático y un Jenkinsfile multi-servicio están diseñados, no
  distribuidos.
- `aegis secret create` no deriva la copia por namespace de la
  credencial del registro; `aegis secret move` lo hace, con la clave
  privada.
- Kyverno solo alcanza registros que firma la CA de la instancia; una
  imagen pública se rechaza con un error `x509`, no con «sin firma».
- Un solo nodo. Sin HA ni multi-clúster: es una plataforma para un
  equipo y sus proyectos, no para una flota. En reposo reserva
  alrededor de 2,5 CPU; un nodo de 4 CPU admite un build a la vez y
  `aegis check` lo dice a través de la cuota de CI.
- Algunos identificadores dentro de la semilla siguen en español a
  propósito: cada uno se mueve con la instancia que lo lee, y el
  glosario lista todos los pendientes.
- Exige leer. La capa más amigable es la próxima pieza de trabajo y se
  construye encima de esta, no en su lugar.

**Lo próximo**, en este orden de intención y sin fechas: la capa
amigable para personas no técnicas y desarrolladores junior, encima de
esta base; el perfil `cloudflare` en una máquina ajena, con sus puertas
pasando de *no evaluable* a medido; más plantillas de aplicación (el
sitio estático y el Jenkinsfile multi-servicio ya diseñados).

## Sobre el idioma

El producto está en inglés: código, identificadores, mensajes, la
semilla y la documentación interna (`docs/`, `seed/platform/docs/`).
`docs/glossary.md` decide qué palabra inglesa representa cada idea y un
check lo hace cumplir. Este README en español es la página principal
por ahora; `README.en.md` es la versión en inglés, y la intención es
que toda la documentación pública termine en inglés. El historial de
commits está en español a propósito: es registro de trabajo, no
producto, y se conserva tal cual — cuenta cómo se encontró cada bug.

## Contribuir, seguridad, licencia

- `CONTRIBUTING.md`: el método es corto y no negociable. Un ítem, un
  commit; un check por cada arreglo; un diente por cada check;
  `aegis verify --profile both` en verde antes de hacer commit, y
  `--teeth NNN` para los checks que tocaste. Nada está *hecho* hasta
  que una corrida lo valida en una instancia real.
- `SECURITY.md`: cómo reportar una vulnerabilidad en privado, con el
  reporte privado de GitHub de este repositorio (*Security → Report a
  vulnerability*), nunca por un issue público.
- Licencia Apache, versión 2.0; ver `LICENSE`.
