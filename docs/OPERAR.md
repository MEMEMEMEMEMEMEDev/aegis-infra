# OPERAR.md — guía para operar una instancia viva

Este archivo es para el agente (AI o humano) que abre una sesión EN
la máquina donde la plataforma aegis está CORRIENDO (la VM de
validación o, a futuro, el host de producción). Su objetivo: que
puedas diagnosticar y operar sin romper nada y sin re-descubrir lo
que ya se aprendió a golpes.

Si vas a MODIFICAR el artefacto → `AGENTS.md` (y hacelo en el repo
del operador, no acá). Contexto histórico → `HISTORIA.md`.

---

## 1. Dónde estás parado

- El clone local vive en `~/workspace/aegis-v2` (rama según la
  corrida; `main` = lo validado).
- El init deja su estado en `init/.init-state/` (markers `*.done`
  por fase + `gates.jsonl`) y sus secretos cifrados en
  `init/.state-secrets/` (`*.enc`, cifrados con la age key).
- La age key vive en `~/.config/sops/age/aegis.key` (chmod 600).
  Para sops/tofu en shells no interactivos SIEMPRE exportar
  explícito: `export SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key`
  (direnv no llega a shells no interactivos).
- Trabajar SIEMPRE dentro de tmux — los cortes de SSH han matado
  procesos largos. PERO: jamás activar pipe-pane/logging de tmux
  durante ceremonias de claves (una key quedó grabada así una vez).

## 2. Estado esperado de una instancia sana

```bash
kubectl get pods -A            # todos Running/Completed
kubectl get applications -n argocd
```

Esperado: ~19 Apps. La MAYORÍA Synced/Healthy, con hasta 3
**OutOfSync/Healthy BENIGNOS y conocidos**: kyverno (CRDs/
defaulting), hello-aegis (digest-pin del Image Updater), root
(cascada). NO son incidentes; no los "arregles".

Namespaces del plano de control: `argocd`, `infra-edge` (traefik +
cloudflared), `cert-manager`, `registry-system`, `jenkins-system`,
`trivy-system`, `kyverno`. Tenant de referencia: `org-canary`
(canary hello-aegis).

Edge sano: `https://aegis.<dominio>` → 200, `argocd.<dominio>` →
200, `jenkins.<dominio>` → 403 anónimo (eso ES éxito, no fallo).

## 3. Diagnóstico: por dónde empezar (en orden)

```bash
# 1) La caja negra de la última corrida — SIEMPRE primero:
jq -r 'select(.result!="pass") | "\(.phase) \(.gate) \(.result)"' \
    ~/workspace/aegis-v2/init/.init-state/gates.jsonl

# 2) Apps y su salud:
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# 3) Un app concreta que preocupa:
kubectl -n argocd get application <app> -o jsonpath='{.status.operationState}' | jq .
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -20

# 4) Jenkins (la API responde con auth; el 403 anónimo es normal):
kubectl -n jenkins-system get pods
kubectl -n jenkins-system logs jenkins-0 -c jenkins --tail=50
```

Reglas de diagnóstico:

- **Convergencia antes de medir**: si algo "falla" segundos después
  de un cambio, probablemente todavía está convergiendo. Esperar la
  estabilidad ANTES de medir; jamás medir `items[0]` de una
  colección con ReplicaSets en cascada — medí el RS VIGENTE.
- **Transitorio ≠ fallo**: firmas de red (dial tcp / i/o timeout /
  lookup / EOF / connection re*) = esperar y reintentar. Error
  determinista con la misma firma 3 veces = causa real, cortar.
- **Un síntoma, varias causas: discriminar ANTES de tocar.** El
  ejemplo canónico: "webhook devuelve 400" puede ser (a) HMAC
  desincronizado o (b) consecuencia de otra cosa (ej. hook borrado,
  RQ agotada aguas abajo). Mirar los logs y las deliveries de
  GitHub ANTES de borrar/recrear nada. Borrar por hipótesis errada
  ya costó una corrida.

## 4. Reglas de NO tocar (violarlas rompe cosas en silencio)

1. **NUNCA imprimir Secrets**: ni `-o yaml`, ni `-o json`, ni
   `.data`. `kubectl get secret <n>` sin `-o` para existencia;
   longitudes con `wc -c` sobre archivo. Sin excepciones, ni "para
   debug".
2. **No `kubectl apply` a mano sobre recursos gestionados**: esto
   es GitOps — ArgoCD con selfHeal REVIERTE tu parche y encima
   queda drift fantasma. El camino es: cambio en el repo → push →
   sync. Si NECESITÁS parchear en vivo (emergencia): pausar el
   auto-sync de esa App PRIMERO, parchear, y saber que al reanudar
   selfHeal vuelve a git.
3. **Sync manual NO hereda las syncOptions del spec** (verificado
   en vivo, v3.4.x): un sync disparado a mano con `operation.sync`
   vacío pierde CreateNamespace/ServerSideApply. Y un sync manual
   FALLIDO envenena el auto-retry ("will not retry"). Preferí
   esperar el auto-sync; si sincronizás a mano, propagá las
   opciones.
4. **`rollout restart` en namespaces con policy de firma**: Kyverno
   NO re-muta UPDATEs sin cambio de imagen — un Deployment admitido
   PRE-policy que referencia un tag queda irreiniciable (deny
   determinista en el ReplicaSet) hasta el próximo bump de imagen.
   Pensalo antes de reiniciar pods en `org-canary`.
5. **El `type` de un Secret es INMUTABLE**: para cambiarlo,
   `kubectl delete` puntual + selfHeal lo recrea desde git. Jamás
   Replace=true permanente en la App.
6. **App Synced+Healthy NO garantiza sus Secrets** (los generators
   KSOPS usan lista explícita): validar `kubectl get secret` tras
   cualquier cambio de secrets.
7. **tofu SIEMPRE por el wrapper** (`platform/tofu/tofu-apply.sh`):
   a pelo faltan TF_VARs y hay destroys fantasma.
8. **Nada de `--insecure`/`accept-first`/`StrictHostKeyChecking=no`**
   en ningún flujo. Lo conocido va declarativo; lo secreto, por el
   operador; TOFU jamás.
9. **Reverts paso a paso**, nunca encadenados con `&&` — cada paso
   con su exit code a la vista.

## 5. Firmas de fallo conocidas (atajo al catálogo)

El catálogo por clase vive en `platform/docs/failure-modes.md`.
Chuleta de las que más aparecen operando:

| Síntoma | Causa probable | Qué mirar |
|---|---|---|
| App ComparisonError permanente | kustomize roto (YAML/entry) — fatal, no esperar | `kubectl kustomize` del dir |
| App ComparisonError intermitente | red (firma dial tcp/timeout) — esperar | reintenta solo |
| Build encolado eterno, init mudo | ResourceQuota agotada | events del ns + uso de la RQ |
| Pod nuevo: connection refused a servicio sano | kube-router aún no programó el ipset del pod fresco | reintentar DENTRO del pod (~30s) |
| "no basic auth credentials" en pull | regcred tipo Opaque (kubelet lo ignora) | `type` debe ser dockerconfigjson |
| Webhook 400 determinista | HMAC desincronizado (o con `\n` final) | deliveries en GitHub + logs |
| DNS del cluster roto tras restart k3s | systemd-resolved stub / nameserver fantasma | runbook §1.9 de VALIDACION.md |
| Jenkins init "cp" crashea | emptyDir contaminado | `kubectl delete pod --force` (emptyDir fresco) |
| cloudflared reinicia seguido | reconexión por red intermitente — NORMAL en dev | nada, es esperado |
| Pod rechazado citando `require-aegis-signature` | imagen sin firmar — la plataforma FUNCIONANDO | pipeline: build+scan+sign |
| Pod rechazado SIN citar la policy | PSS o quota, NO Kyverno | el mensaje del deny dice cuál |

## 6. Los tools de recuperación

Corren out-of-band (nunca dentro del init). Todos con dry-run por
default donde aplica:

```bash
cd ~/workspace/aegis-v2
export SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key

init/aegis-backup.sh     # bundle age-cifrado de los 3 estados
                         # (.state-secrets, .init-state, tfstate) con
                         # ROUNDTRIP verificado. La age key JAMÁS va
                         # en el bundle (guard activo).
                         # Escribe en $AEGIS_RESPALDOS/plataforma/.
init/aegis-restore.sh <bundle>   # inverso; se niega a pisar estado
                                 # existente sin --force
init/aegis-rotate.sh             # SIN argumentos: el menú de rotación
                                 # (ver abajo). Con nombre y --yes,
                                 # sigue andando el contrato viejo.
init/aegis-destroy.sh [--yes]    # tofu destroy del edge CF + purga
                                 # tfstate; dry-run muestra el plan
```

### Rotar una credencial

```bash
init/aegis-rotate.sh          # inventario, edad y radio de cada una
```

El menú lista lo rotable con su EDAD y, sobre todo, con el **radio**: qué
se rompe si esa rotación sale mal. El radio se imprime *antes* de la
confirmación, que es cuando sirve.

Lo que hace por cada credencial: archiva el `.enc` anterior en
`.state-secrets/.previo/`, lo invalida del store, corre la fase que lo
regenera y sincroniza el tercero, y **verifica ejerciendo el consumidor
real**. Esa última parte es la que antes no hacía nadie.

Tres cosas que conviene tener presentes:

- **No arranca si la red está mal.** Preflight de GitHub, Cloudflare,
  cluster y age key antes de tocar el primer `.enc`. Sobre esta máquina
  eso no es paranoia: es lo que evita quedar a medio sincronizar.
- **Reintenta el transporte, no el veredicto.** Un timeout se reintenta
  hasta tres veces; un «Permission denied» o un webhook que contesta 400
  **no**. Ahí el remoto ya contestó, y contestó que no.
- **Si falla, no revierte solo.** Te dice en cuál de los cuatro lugares
  —git, cluster, tercero, store— quedó cada mitad, y con qué comando se
  cierra la brecha. Después, `--continuar` retoma la tanda.

Se niega a rotar `cosign_*` y la age key (irreducibles, cada uno con su
protocolo en `platform/docs/protocols/`) y delega `registry_pass` en
`bin/aegis-registro`.

No commitea ni pushea: eso lo da una persona.

### Preguntar si una credencial funciona, sin rotarla

```bash
init/aegis-rotate.sh --verificar              # todas las del inventario
init/aegis-rotate.sh --verificar hmac_jenkins # una sola
```

Ejerce el consumidor REAL de cada una: ping del webhook que tiene que
dar 200 *y* firma inventada que tiene que dar 400; `ssh -T` con la clave
del Secret vivo; login real en ArgoCD y en Jenkins; `tofu plan`;
certificados Ready. Cuatro resultados posibles, y el tercero importa
tanto como los otros:

| | significa |
|---|---|
| `✓ funciona` | el consumidor real la aceptó |
| `✗ la RECHAZA` | el remoto contestó, y contestó que no |
| `? no se pudo llegar` | falló la MEDICIÓN, no necesariamente la credencial |
| `! sin diente escrito` | nadie la mide. **No es verde.** |

### Cloudflare Access, y por qué `--verificar` tiene dos dientes ahí

`argocd.<dominio>` y `jenkins.<dominio>` están detrás de Cloudflare
Access. Eso cambia lo que significa un `curl` contra ellos: sin
credencial, Cloudflare contesta **302 al login desde su propio borde**
— la petición no entra al túnel, no toca traefik y no ve la app.

Un chequeo que acepte ese 302 como «responde» queda verde con el
cluster entero apagado. Por eso todo lo que sondea esos hostnames pasa
por `edge_origen_responde` (`init/lib/access.sh`), que atraviesa Access
con el service token y **separa tres desenlaces que antes eran uno**:
el origen contestó / Access interceptó / no hubo respuesta.

Y por eso `--verificar access_st_id` mide dos cosas, no una:

| diente | qué prueba |
|---|---|
| **con** el service token → llega al ORIGEN | el token sirve |
| **sin** el token → Access intercepta | Access está de verdad protegiendo |

Sin el segundo, el primero no probaría nada: si Access estuviera caído,
todo el mundo llegaría al origen y el verificador estaría igual de
verde.

Las credenciales de Access son tres y las produce el init: el token de
API (`cf_access_token`, fase 15) y las dos mitades del service token
(`access_st_id` / `access_st_secret`, fase 25, desde los outputs de
tofu). Las dos mitades se rotan **siempre juntas** — Cloudflare las
emite en par.

El token de API de Access es **separado** del token del túnel a
propósito: el job `edge-apply` de Jenkins recibe el del túnel, y si ese
token pudiera editar Access, un CI comprometido podría sacarse a sí
mismo de detrás de Access.

### La password de admin de ArgoCD

Desde el 2026-08-12 vive en el store, cifrada con la age key — no hay
que anotarla aparte (principio D11: el operador resguarda la age key y
nada más). Para leerla:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key
sops -d --input-type binary --output-type binary \
  init/.state-secrets/argocd_admin_pass.enc
```

`argocd-initial-admin-secret` ya no existe: se borró al rotar, que es lo
que ArgoCD espera que hagas y nadie hacía.

### Los respaldos: dos mitades y un disco aparte

Son DOS y hacen falta las dos. `aegis-backup.sh` trae el ESTADO de la
plataforma; `platform/bin/aegis-respaldo` trae los DATOS de los
inquilinos. Con el estado solo se levanta una plataforma vacía; con los
datos solos se tiene un dump que no se sabe dónde poner.

```bash
export AEGIS_RESPALDOS=/ruta/en/OTRO/disco/aegis-respaldos

init/aegis-backup.sh                       # el estado -> plataforma/
platform/bin/aegis-respaldo --capturar     # los datos -> uno por organización
platform/bin/aegis-respaldo --listar   <bundle.age>
platform/bin/aegis-respaldo --restaurar <bundle.age> --org <org>
```

El árbol que producen:

```
$AEGIS_RESPALDOS/
  .aegis-destino                     el UUID del filesystem, anotado
  plataforma/aegis-estado-<ts>.age
  org-<nombre>/aegis-datos-org-<nombre>-<ts>.age
```

Tres cosas que conviene saber, y las tres nacieron de un fallo que no
avisa:

- **Un bundle por organización.** Restaurar una no obliga a abrir el
  resguardo de las demás —que lleva datos de terceros—, y la pregunta
  que responde `aegis-chequeo` deja de ser "¿hay respaldo?" para ser
  "¿tiene respaldo CADA organización?". Las enumera desde los contratos:
  una organización que declara datos y no tiene bundle es un FALLO, no
  un silencio.
- **El destino va en OTRO disco**, y la primera captura anota el UUID de
  su filesystem en `.aegis-destino`. Si no coincide, no se escribe nada.
  Sin esa guarda, un segundo disco que el escritorio monta al iniciar
  sesión —o sea, no montado durante el arranque— deja la ruta como
  directorio vacío del disco raíz, y el respaldo aterriza ahí: éxito
  reportado, cero protección, y la copia que debía sobrevivir al disco
  viviendo en el disco.
- **`AEGIS_BACKUP_SINK`** saca el bundle de la máquina. Mientras no esté
  configurado, el chequeo avisa en cada corrida, y tiene razón.

#### El cifrado, y la única forma de perder todo esto

Los dos bundles son **archivos `age`**. Se cifran con la clave PÚBLICA
del par de aegis y se abren con la privada, la misma
`~/.config/sops/age/aegis.key` que usa SOPS para los `.enc` del repo. Un
solo par para las dos cosas: no hay una segunda clave que administrar.

Cifrar no necesita la privada. `--capturar` deriva la pública de la
clave que tengas a mano (o la lee de `AGE_PUBLIC` / `init/.age-public`),
así que una máquina puede respaldar sin poder leer lo que respaldó.

**La age key NUNCA entra a un bundle.** Los dos scripts lo comprueban
antes de cifrar y ABORTAN si encuentran material de la clave adentro; el
check 80 de `verify-static` lo exige. El motivo es el obvio: el huevo y
la gallina en el mismo canasto no protegen de nada. La consecuencia
también es obvia y hay que decirla en voz alta:

> **Si perdés la age key, cada `.age` de ese disco es un ladrillo.** No
> hay recuperación, ni parcial ni por fuerza bruta, ni la tenemos
> nosotros. La clave es EL irreducible: va a tu resguardo offline, y ése
> es un lugar distinto del disco de respaldos — si viven juntos, un solo
> accidente se lleva las dos mitades.

Y por qué el cifrado no es ceremonia: el bundle del estado lleva el
`terraform.tfstate` del túnel **con el `tunnel_token` en claro**. Ahí no
hay una segunda capa; el `age` del bundle *es* lo que lo protege.

**Abrir uno sin la herramienta.** Es lo que importa en el escenario para
el que existe un respaldo: un disco enchufado a otra máquina, sin repo y
sin aegis. Alcanza con `age` y `tar`, y produce SQL y archivos planos:

```bash
age -d -i ~/.config/sops/age/aegis.key <bundle>.age | tar -xzvf -
```

Los `--listar` / `--restaurar` de `aegis-respaldo` son comodidad —
validan el manifiesto, comparan credenciales, restauran a la base
correcta—, no un formato propietario. Verificado el 2026-08-22 contra un
bundle real.

**Y se verifica en el momento de escribirlo.** Las dos herramientas
hacen ROUNDTRIP: descifran el bundle recién creado con la clave privada
y lo comparan byte a byte con lo que capturaron. Sin eso se tiene
«backups»; con eso, restauración probada — que es lo que exige la Ley
21.719 y lo que uno quiere el día que hace falta. Si la privada no está,
el bundle se produce igual pero se marca NO-VERIFICADO, a los gritos.

Advertencias:

- Rotar `cosign_key` invalida TODAS las firmas emitidas → protocolo
  `platform/docs/protocols/issue-cosign-keypair.md` §5 (re-firmar lo
  desplegado). El tool ya lo rechaza; no lo fuerces por otro camino.
- Re-correr una fase NO rota un secreto por sí solo (el store
  restaura el `.enc` viejo): rotar = `aegis-rotate --yes` PRIMERO,
  fase después. Checklist: `platform/docs/protocols/rotation-checklist.md`.
- `destroy --yes` es también la limpieza de "nube sucia" antes de
  una corrida nueva.

## 7. Cuándo parar y escalar al operador

- Cualquier acción irreversible: borrar recursos externos (webhooks,
  DNS, repos), `destroy --yes`, rotación de irreducibles.
- Cualquier cosa que requiera ver material de secretos en claro.
- Tu hipótesis contradice la evidencia del operador → parar y
  mostrar los datos (histórico: 2 veces el operador refutó el
  diagnóstico del agente con evidencia; las 2 tenía razón).
- El cluster quedó en un estado que el init no contempla (ej.
  auto-sync envenenado "will not retry") → NO improvisar cirugía;
  la respuesta puede ser snapshot limpio + re-init, y esa decisión
  es del operador.

Al cerrar una sesión de operación con hallazgos: dejar la evidencia
(gates.jsonl, logs relevantes, comandos ejecutados) en un archivo
para el operador — el post-mortem no puede depender de que alguien
haya leído la pantalla.

---

*Última actualización: 2026-07-24, al cierre de VERSIÓN 2.*
