# Caminos — diseño de los protocolos de app, SIN código todavía

Alcance: cómo un usuario crea una app en aegis y la lleva a prod sin
que sea terrible, cómo crece después, y cómo el catálogo de la
plataforma crece con él. Mismo criterio que observability/design.md:
acá se toman las decisiones; el bash llega después y ya las encuentra
tomadas. Nada de este documento existe todavía salvo lo marcado [HOY].

## 0. Principios (los que ordenan todo lo demás)

1. **El contrato es la única verdad.** `orgs/<n>.yaml` es la entrada
   de la que TODO se deriva. Una plantilla genera contratos; un camino
   los escribe a mano; ninguno crea una segunda fuente de verdad.
2. **Archivos y mundo, separados con pausa en el medio.** Generar es
   inocuo y revisable (git diff); ejecutar contra el mundo (GitHub)
   es consciente y posterior. Es el plan/apply de tofu, aplicado al
   onboarding. La frontera vive a nivel de SUBCOMANDO (ver §3).
3. **La plantilla se evapora.** Instancia contrato + código inicial y
   desaparece: desde ese momento el usuario es un artesano más. Cero
   apps "atadas a su plantilla" — no somos un framework.
4. **Converger, no ejecutar.** Todo comando re-corrido con el trabajo
   hecho termina en "nada que hacer". Crear-si-falta, jamás
   recrear-por-las-dudas.
5. **Rieles firmes en el centro, libertad en los bordes.** Los puntos
   de extensión (sustratos, plantillas, checks) quedan documentados
   con checklist para que cada instancia personalice SU aegis por las
   puertas marcadas. Lo que no se personaliza: la frontera de §0.2,
   la firma, el contrato como verdad.

## 1. Los tres caminos

| camino | quién es | qué hace |
|---|---|---|
| artesano | quiere IaC puro y control | escribe `orgs/<n>.yaml` a mano; corre `aegis-org` + `aegis-secreto` [HOY] + `aegis-app aplicar` (nuevo, cierra los pasos GitHub) |
| plantilla | quiere partir de algo que ya funciona | `aegis-app nueva <org> --plantilla <p>` → contrato + esqueletos; revisa; `aegis-app aplicar` |
| silencioso | avanzado, no quiere demo ni ruido | `DEMO=ninguna` en `aegis-init.conf` → plataforma pelada; los otros dos caminos quedan disponibles, sin usar |

Misma maquinaria, tres puertas. Ningún camino encierra: el usuario de
plantilla edita su contrato a mano al día siguiente y nadie lo nota.

Config nueva: `DEMO=portafolio|ninguna` (default `portafolio`) en
`aegis-init.conf` — campo T1, lo pregunta el wizard.

## 2. `aegis-org` gana dos derivaciones (van de 8 a 10)

Ambas siguen el patrón existente: rederivación total del bloque
propio, idempotente, precedente de tocar archivos fuera de
`organizations/` (el borde en `main.tf`, las keys en argocd-secrets).

**2a. El job multibranch de Jenkins.** Hoy: 20 líneas de job-dsl
copiadas a mano en `k8s/base/platform/jenkins/values.yaml` por cada
app — derivable del `repo:` del contrato y no se deriva (el hueco #2
del mapa de onboarding). Diseño: un bloque delimitado en ese
values.yaml, propiedad del generador:

    # --- DERIVADO por aegis-org (jobs de tenant): no editar a mano ---
    ...un job por cada servicio con repo, de todos los contratos...
    # --- FIN DERIVADO ---

Fuera del bloque, lo escrito a mano sobrevive (los jobs de plataforma
como mirror-images). Deuda de migración anotada: los 5 jobs actuales
están a mano y `org-canary` no tiene contrato — migran al bloque
cuando su org tenga contrato, no antes.

**2b. El Jenkinsfile instanciado.** El template tiene 1 CHANGEME en
452 líneas: se instancia desde el contrato (`IMAGE = '<org>-<svc>'`)
al staging del esqueleto (ver §3). El template deja de copiarse a
mano; sigue siendo UNO, versionado en docs/protocols/templates/.

## 3. `aegis-app` — el comando nuevo, y dónde vive su frontera

Dos subcomandos, y la regla de la casa grabada en la cabecera:
**`nueva` escribe archivos y JAMÁS toca el mundo; `aplicar` toca el
mundo y JAMÁS escribe en los repos.** (espejo del "NO HABLA CON EL
CLUSTER" de aegis-org; candidato a check de verify-static.)

**`aegis-app nueva <org> --plantilla <p>`** (solo archivos):
1. instancia `orgs/<org>.yaml` desde la plantilla (aborta si ya
   existe: un contrato vivo no se pisa — se edita a mano)
2. instancia los esqueletos de código a un staging LOCAL:
   `.aegis-app/<org>/<svc>/` (gitignorado: destino es OTRO repo,
   versionarlo acá sería el error de platform/ de nuevo)
3. corre `bin/aegis-org aplicar` (que ya incluye §2a y §2b)
4. corre `bin/aegis-secreto --todos`
5. imprime el diff pendiente y el siguiente paso
Re-correrla converge; sin `--plantilla` sirve al artesano que ya
escribió su contrato (salta 1-2).

**`aegis-app aplicar <org>`** (solo mundo, lee lo generado):
| paso | guarda de idempotencia |
|---|---|
| repo GitHub por servicio con `repo:` | existe → no crea. `gh repo create` solo si falta |
| push del esqueleto desde staging | SOLO si el repo está VACÍO (0 commits). Un repo con historia jamás se pisa — el artesano trae el suyo y este paso es no-op |
| deploy key | compara fingerprint contra la pública generada; registra solo si falta (`gh repo deploy-key add` — el paso "irreducible" de aegis-secreto, reducido) |
| webhook | delega en `bin/aegis-webhook --aplicar` [HOY, ya idempotente] |
| veredicto | tres desenlaces por paso: hecho / ya estaba / NO SE PUDO — el tercero es aviso, no visto bueno (enfermedad E) |

Queda humano a propósito: el commit+push del repo de plataforma (acto
de gobierno) y el `tofu apply` del borde (del operador por diseño,
#46). `aegis-app aplicar` termina diciéndolos, no haciéndolos.

## 4. Plantillas

Estructura: `seed/templates/<nombre>/`
- `contract.yaml.tpl` — el contrato con `__ORG__` y `__DOMINIO__`
- `repos/<svc>/…` — código inicial completo por servicio: fuente,
  `Containerfile`, `k8s/base/` + overlay (el Jenkinsfile NO va acá:
  lo instancia §2b desde el template canónico)
- `README.md` — qué levanta, qué decisiones tomó, y que se evapora

Catálogo chico A PROPÓSITO — cada plantilla es código vivo que se
pudre, y la defensa es mantener pocas y vigiladas:
- `base` — un servicio http pelado. La mínima que compila y despliega.
- `portafolio` — la demo del init (ver §5).
- `ecommerce` — la insignia. Se construye primero COMO APP REAL en la
  instancia viva usando estos protocolos (es su banco de pruebas);
  asciende a plantilla cuando madure. No antes.

## 5. El portafolio-demo

Stack elegido por presupuesto de podredumbre mínimo:
- front `estatico`: HTML/CSS/JS plano. Cero build, cero node_modules
  — no puede pudrirse porque no hay árbol que se pudra.
- api `http`: Express. Dos dependencias reales (express, pg).
- `postgres`: sustrato de plataforma [HOY].
- `bucket`: Garage [HOY en instancia; semilla: PENDIENTE #42].
  Aclaración de nombres: Garage es el SERVIDOR (self-hosted, en el
  cluster); "S3" es el PROTOCOLO que habla — el estándar de facto del
  object storage, inventado por Amazon pero hablado por todos. Cero
  AWS involucrado: los datos jamás salen del cluster. OJO: el cliente
  S3 del backend es donde se cuela la única dependencia gorda — el
  SDK oficial pesa cientos de paquetes; evaluar firmar SigV4 con una
  lib mínima (por debajo es HTTP normal con firma).
- pipeline COMENTADO línea a línea: la demo también enseña.

**La demo como canario de podredumbre**: una imagen pinneada no
envejece a salvo — acumula CVEs sentada, y el scan corre solo al
construir: una app que nadie pushea NO SE RE-ESCANEA NUNCA. El job de
la demo lleva cron (patrón edge-chequeo) para construir periódicamente
sin cambios: el envejecimiento se vuelve build rojo visible en vez de
silencio. Trabajo gratis que hace por existir.

Init: fase nueva `90-demo.sh` — si `DEMO=ninguna`, no-op con log; si
no, corre `aegis-app nueva portafolio --plantilla portafolio` +
`aplicar` + commit (el init SÍ commitea: es bootstrap, no gobierno).
La demo prueba el camino de plantilla completo en cada bootstrap.
Desmontar después: `aegis-org borrar` [HOY].

## 6. Protocolo: crecer el catálogo de sustratos

Para redis, una cola, o lo que el futuro pida. La mitad ya existe
[HOY]: mirror-images trae+escanea+firma terceros ("redis, postgres,
lo que sea", dice su propio Jenkinsfile). Checklist completa:

1. línea en `mirror-images/images.txt` (origen POR DIGEST) + correr
   el job → espejada y firmada
2. entrada en `services.yaml`: imagen del registry interno por
   digest, recursos, forma de la credencial. La decisión se toma UNA
   vez, para todas las orgs
3. derivación en `aegis-org`: `tipo: <sustrato>` en un contrato →
   su workload derivado (patrón postgres [HOY])
4. categoría en `aegis-secreto` para su credencial
5. si cambia una GARANTÍA (no una capacidad): check en verify-static
   (regla de PENDIENTE.md §5)

Decisión diferida A PROPÓSITO: redis vs rabbit vs nada. El e-commerce
lo pedirá con evidencia; con esta checklist, agregar un sustrato
cuesta una tarde, no una arquitectura. Apuesta anotada: redis primero
(sesiones/carrito); cola solo ante trabajo asíncrono real, y ese día
la pelea es rabbit vs redis-streams vs tabla en postgres.

## 7. Protocolo: dependencias de app (el pipeline rojo con salida)

[HOY] el scan bloquea CRITICAL/HIGH — eso es el gate haciendo su
trabajo, no un fallo. Lo que falta es la puerta de salida del dev:

1. primero: subir la versión de la dependencia (el fix normal)
2. sin fix disponible: excepción DECLARADA — `trivyignore` del repo
   de la app (patrón mirror-images/trivyignore.yaml [HOY]) con CVE,
   justificación y **fecha de vencimiento** obligatoria
3. excepción vencida = build rojo otra vez. Sin vencimiento es deuda
   invisible; con vencimiento es deuda agendada
4. el stage de scan lee el trivyignore del repo y lista en el log
   TODA excepción activa y sus días restantes (visible, no enterrada)

## 8. Fuera de alcance de esta versión (decidido, no olvidado)

- La ceremonia de clave AI (6 pasos manuales): problema con forma
  propia, el e-commerce no la necesita. AI queda pendiente-y-abierto.
- Monorepo: v1 es repo-por-servicio (calza con el multibranch [HOY]).
  Un monorepo exige filtrado por path en Jenkins — se evalúa si una
  app real lo pide.
- Migrar los 5 jobs a mano y las orgs sin contrato (canary,
  ecommerce-heredado): deuda anotada, no bloquea.
- Access por contrato (hostnames privados de tenant): hoy Access es
  de plataforma; si una org pide panel privado, se diseña aparte.

## 9. Orden de construcción (cada paso usable por sí solo)

1. §2a+§2b — aegis-org deriva jobs y Jenkinsfile (mata los huecos
   más dolorosos sin comando nuevo)
2. §3 `aegis-app aplicar` — cierra repo/key/webhook para contratos
   existentes (el artesano ya gana)
3. §3 `aegis-app nueva` + §4 plantilla `base`
4. e-commerce EN LA INSTANCIA usando todo lo anterior — cada fricción
   es bug del protocolo; al madurar, asciende a plantilla
5. §5 plantilla portafolio + fase 90-demo + `DEMO=` en el conf
6. todo vuelve a la semilla (`aegis-semilla traer` / init) — regla
   estructural: lo que no entra por semilla no entró

Vara de aceptación global: el test del amigo — un dev externo, con un
clone y un contrato, llega a URL pública sin el operador en la sala.
