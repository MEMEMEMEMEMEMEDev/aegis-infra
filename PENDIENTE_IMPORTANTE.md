# PENDIENTE_IMPORTANTE — relevo de la misión de revisión (2026-10-14)

Este archivo es el relevo para quien siga el trabajo de la rama
`claude/tender-goodall-58iybq`. Lo escribió el agente que hizo la revisión del
2026-10-13 y las correcciones de las secciones 0–3, 4A y parte de 4B. Lo que
está hecho está en el CHANGELOG (entrada «2026-10-14») y en los mensajes de
commit; aquí va lo que falta, en el orden en que conviene hacerlo, con lo que
ya se sabe de cada ítem para no volver a investigarlo.

## 0. Reglas que no se negocian (están en `docs/AGENTS.md` y `CONTRIBUTING.md`)

- Producto en inglés (código, comentarios, textos de producto); el vocabulario
  lo vigila el check 111 (excluye `*.md`). El producto no nombra máquinas ni
  personas (checks 116 y 117): ni VMs de laboratorio, ni logins, ni nombres.
- Un ítem = un commit (Conventional Commits; el mensaje dice qué se encontró y
  por qué). Cada arreglo lleva su check en `verify/checks/NNN-slug.sh` (con
  sidecar `NNN.py` si conduce algo) y su diente en `verify/teeth/NNN.sh`: cada
  `red_N` debe poner el check en rojo, cada `control_N` debe dejarlo en verde.
  El helper `_sub` de los dientes exige exactamente una aparición del ancla.
- Antes de cada commit: `CI=1 ./bin/aegis verify --profile both` en verde
  (desde 4B-2 es un solo pase: ~1 min 20 s) y `--teeth NNN` de lo tocado.
  `CI=1` porque el check 117 mide el login y como `root` se pone rojo (ese es
  uno de los pendientes). Los dientes ya no necesitan `AEGIS_VERIFY_RETRY=1`
  (arreglado en 4B-1).
- Nada está «hecho» hasta que una corrida en instancia real lo valida. Aquí no
  hubo clúster: cada entrada del CHANGELOG dice «Not yet run on a live
  instance» y qué debe correr la instancia.
- Herramientas que la suite necesita y que no se instalan solas: `sops`
  (versión fijada en `seed/platform/ansible/inventory/group_vars/all.yml`,
  `userland_pins.sops`), `age`/`age-keygen`, `kubectl` (sin él fallan 131, 215
  y 220: ese es el ítem M-7), `script`(1), `shred`, `jq`, `python3-yaml`. Los
  checks nuevos 283–287 conducen sops y age reales sobre una clave de usar y
  tirar.
- Los sidecars nuevos construyen su entorno SIN las variables de la instancia
  (`AEGIS_*`, `PLATFORM_DIR`, `SOPS_AGE_KEY_FILE`, `AGE_PUBLIC`): el
  verificador las exporta y un driver que las hereda escribe en la instancia
  real (pasó el 2026-10-14 con el 285). Copiar el patrón de `verify/checks/286.py`.

## 1. Estado de la rama

Commits de código sobre la portada (todos con suite verde y dientes mordiendo):

| commit | qué | check |
|---|---|---|
| bbdadea | Secret cifrado antes de entrar al repo; `git_commit_if_changes` rechaza `*.enc.yaml` sin `sops:` | 283 |
| 2845972 | `inherit_errexit` en los libs; `_gen_guard`; `persist_secret` rechaza vacío | 284 |
| ff23038 | la copia de la clave age vive en el tmpfs de la fase (traps EXIT/INT/TERM) | 285 |
| 0ad3944 | `tofu-apply.sh`: re-cifrado y shred en `finish_state` por trap | 277 ampliado |
| 407d46c | `aegis data` y `aegis state backup\|restore`: staging bajo la instancia, shred, señales | 286 |
| 9db0230 | los drivers 283–285 limpian las variables de la instancia | — |
| 4debb64 | `aegis init-log`: dosier 0600 en dir 0700 | 287 |
| c484c9e | el staging del bundle de estado cae a disco si no cabe en tmpfs | 286 |
| f2d71b4 | el pase de confirmación del verificador conserva los argumentos; los dientes no lo repiten | harness 12 |
| 08e2271 | `--profile both` es un pase mientras ningún check lea el perfil | harness 13 |

Una revisión adversarial automática de los seis primeros commits se lanzó y
no se alcanzó a leer su resultado: **conviene que el siguiente agente haga su
propia lectura crítica de `git diff cd3f776..08e2271`** antes de seguir, con
estas preguntas: ¿`sops --filename-override` con ruta absoluta casa con el
`path_regex` de `seed/platform/.sops.yaml` igual que el cifrado in-place?
¿Algún `$( )` del producto deja de sobrevivir con `inherit_errexit` (funciones
llamadas dentro de una sustitución con comandos que fallan a propósito)?
¿Rompe algo en una instancia viva el nuevo `~/aegis/.staging`?

## 2. Lo que queda, en orden

### 4B — verificador (lo barato y de alto valor)

1. **`--with-charts` como check propio.** Hoy la rama de charts está dentro
   del check 074 detrás de `[[ "${1:-}" == "--with-charts" ]]`, que nunca es
   cierto (check() no recibe argumentos), y además emitiría varios veredictos
   (el verificador lo contaría como BUG). Hacer un check 288 que lea
   `AEGIS_VERIFY_WITH_CHARTS` (el verificador ya lo exporta) y `helm`, y haga
   `skip` con nombre cuando falte cualquiera de los dos; un solo veredicto;
   quitar la rama muerta de 074. Sus dientes solo se validan con helm y red.
2. **Dientes «no aplicables aquí», declarados.** En `_one_tooth`
   (`libexec/aegis-verify`) un `red_N`/`control_N` que devuelva 75 se reporta
   como «not applicable here: <motivo>» (la función imprime el motivo), no
   cuenta como muerde ni como fallo, y la línea resumen lo dice. Prueba del
   harness. Con eso: `verify/teeth/117.sh` `red_1`/`red_4` devuelven 75 cuando
   `_who117` no tiene identidad medida; `verify/teeth/120.sh` `red_1`, `red_2`,
   `red_4` cuando `_val` está vacío (no hay `aegis.conf`) y `red_3` cuando
   `$HOME` es `/` o `/root` (el sidecar 120 no los mide). Medido: esas seis
   mutaciones «no muerden» en CI y como root por esto, no por los checks.
3. **117 con `root`.** `_name_absent` de `verify/checks/117-*.sh` mide el login
   si tiene 4+ caracteres: `root` se mide y aparece en todo el producto
   («root of trust», `AEGIS_ROOT`), así que como root el check está rojo salvo
   con `CI=1`. Declarar `root` (y los logins de rol: `runner` ya, `ubuntu`,
   `admin`, `vagrant`) como «names nobody: NOT measured», igual que `aegis`.
   En el mismo commit: el comentario de 117 dice «Measured on alpha-ubuntu» y
   hay nombres de VMs de laboratorio (`alpha-arch`, `alpha-ubuntu`,
   `alpha-debian`) y una persona nombrada en comentarios del producto
   (`bin/aegis:45`, `lib/access.sh:184`, `libexec/aegis-app:404,848,1182,1364`,
   `libexec/aegis-image:614`, `init/phases/80-supply-chain.sh:216,361,368`,
   `init/phases/35-gitops.sh:349`, `libexec/aegis-check:1011`,
   `libexec/aegis-dev:39`, `libexec/aegis-state:42`, y los orígenes de los
   checks 276, 265, 282 y sidecars 260, 272, 273). Reescribir como «a lab VM
   (Arch)», «a user's instance (their H-07 report)». Buscar con
   `grep -rn 'alpha-[a-z]*' bin lib libexec init verify seed docs`.
4. **199 corre un diente de muestra.** Hoy solo comprueba que exista
   `verify/teeth/NNN.sh`. Elegir un check de forma determinista por el HEAD
   (`git rev-parse HEAD`, o un hash de la lista de dientes si no hay git) y
   correr `aegis-verify --teeth N --profile <actual>`; rojo si no muerde.
   Cuesta 20–60 s por pase.
5. **009 ampliado.** Hoy audita `|| true` solo en `init/phases`. Clasificación
   ya hecha de los 129 sitios de `lib libexec init seed/platform/docs/protocols/templates seed/canary`:
   71 lecturas con vacío por defecto (A), 49 limpiezas best-effort (B), 6
   idiomas (`shift || true`) (C) y **3 reales (D)**, donde el vacío cae en la
   rama permisiva:
   - `lib/access.sh:207` (`hook_newest_delivery`): un fallo transitorio de
     `gh api` devuelve 0, igual que «sin entregas», y la puerta
     `delivery-push-2xx` de la fase 60 puede aceptar una entrega vieja. Arreglo:
     `|| return 1` y en `init/phases/60-webhook.sh:104` `die` si no se pudo leer.
   - `lib/common.sh:586` (`argo_sync`, `prev_started`): si el apiserver no
     contesta, `prev_started=""` y un `Succeeded` viejo se lee como el sync
     nuevo. Arreglo: `|| { log_error …; _gate_record … fail 0; return 1; }`.
   - `lib/common.sh:625` (`argo_sync`, `spec_opts`): si la lectura falla se
     dispara el sync manual sin `ServerSideApply,CreateNamespace` (el Finding
     D v1.2 que el propio comentario describe). Mismo arreglo.
   Patrones para la exención automática en el check ampliado (ERE, sobre la
   línea `file:NN:texto`, después de `nc_hits`): `\|\| true\)"?$`,
   `\$\([^()]*\|\| true\)`, `>&2 \|\| true$`,
   `(2>/dev/null|>/dev/null 2>&1) \|\| true$` emparejado con una lista
   negativa de verbos nunca exentos (`sops|age|openssl|cosign|install|tee|tofu|ansible-playbook|git (push|commit|fetch)|kubectl (apply|patch|delete)|systemctl enable`),
   `\bshift( [0-9]+)?( 2>/dev/null)? \|\| true`, `git .*commit`,
   `\|\| true['"]?[,)]*$`. Sitios que ningún patrón cubre y van a una lista
   explícita por texto (no por número de línea): `lib/jenkins.sh:236,238`,
   `libexec/aegis-ai:542`, `lib/common.sh:704,729,748` (el verbo `kubectl
   patch` está en la línea anterior), `libexec/aegis-destroy:176` (tofu plan
   en modo dry-run), `libexec/aegis-check:1151`,
   `init/phases/80-supply-chain.sh:704`. Los tres D se arreglan primero; con
   eso lo que queda tras los patrones es nada. Diente: devolver el `|| true` a
   cada D.
6. **`--harness` en CI**: un paso más en `.github/workflows/verify.yml`.
7. **Dientes que no muerden por el entorno.** `verify/checks/266.py`: el driver
   hereda `GIT_TERMINAL_PROMPT=0` del entorno (los agentes lo exportan), así
   que `red_9` no muerde; quitarla de `os.environ` durante la prueba.
   `verify/checks/131.py`: `red_1` no muerde porque sin `plans.yaml` en la
   instancia el paso `capacity:plans` sale `not-evaluable` y el check se
   conforma con cualquier `not-evaluable`; darle un `plans.yaml` (copiar
   `seed/platform/plans.yaml` a un `AEGIS_HOME` de prueba) y exigir que ningún
   paso `capacity:*` salga `already` con allocatable 0 cuando el apiserver no
   contesta.
8. **M-7, herramientas ausentes.** Sin `kubectl`, `libexec/aegis-capacity`
   (`_kubectl`, línea ~50) y el productor de `aegis update metrics` mueren con
   `FileNotFoundError` en vez de declarar `not-evaluable`: capturar `OSError`
   como `RuntimeError("kubectl is not installed")`. En el verificador, un
   preámbulo que declare las herramientas que la suite necesita y un helper
   `need_tool` en `verify/lib.sh` que convierta la ausencia en `skip` con
   nombre, usado por los checks que conducen herramientas reales (277, 278,
   283–287).
9. Al cerrar 4B: la cola real de `aegis verify` que cita el README (sección
   «Míralo») cambió de forma (un solo pase y el aviso): recapturarla y poner
   la fecha.

### 4C — init/CLI (lo que el informe llamó CL-1..CL-4)

- **CL-3 códigos de salida** (contrato en `share/exit-codes.txt`):
  `lib/aegis/cli.py` sobreescribe `error()` → 3; `bin/aegis` comando
  desconocido → 3 (hoy 2); `libexec/aegis-init` flag desconocido y `--from`
  sin valor → 3 (hoy 2 y 1); `aegis check` sin apiserver → 2 (hoy 1);
  `aegis-data` `die()` con código; envoltorio común de excepciones → 2. Lo
  medido está en `scratchpad/audit/14-exit-codes.txt` de la sesión (no está
  en el repo): `nosuchcmd`→2, `init --bogus-flag`→2, `init --from` sin
  valor→1, `capacity|data|org --bogus`→2; `check --bogus` y `verify --bogus`
  ya dan 3. Check que recorra `libexec` + diente.
- **CL-2 `--reset-state`**: corre antes de validar flags y borra estado de
  otros comandos (diario de rotación, ventanas, cadencia). Después de
  validar, solo marcadores de fase; archivar `gates.jsonl`.
- **CL-1 `--check` no es ensayo en seco**: fases hechas se saltan;
  `lib/secrets.sh` y `lib/jenkins.sh` ignoran `CHECK_MODE`; la fase 10 escribe
  `.age-public`. Respetar `CHECK_MODE` (no escribir, no disparar builds) y
  marcar en `gates.jsonl` las puertas medidas en `--check`.
- **CL-4 parser de `aegis.conf`**: bash hace `source` y
  `lib/aegis/paths.py:90-112` lo parsea a texto: comentarios en línea y
  `$HOME` difieren; el asistente escribe sin escapar. Check que compare ambos
  lectores sobre `init/aegis-init.conf.example`.
- Preámbulo canónico (V-102) en `libexec/state/*` y `libexec/dev/*`.

### 4D — semilla y cadena de suministro (estático primero)

- **SC-3**: `seed/platform/docs/protocols/templates/Jenkinsfile.app:590-607`
  el escaneo de apps falla abierto si trivy-server no responde en 5 s y la
  imagen se firma igual; `:658-661` un `trivyignore.yaml` del repo se pasa
  sin validar. Fallar cerrado (excepción explícita solo antes de la fase 80,
  si existe) y validar el fichero contra la política de deuda (fechado, sin
  KEV). Check sobre el Jenkinsfile + diente.
- **K8-1**: la lista negra del AppProject (`lib/aegis/org.py`) y el canario no
  cubren `networking.k8s.io/Ingress` (Traefik con `providers.kubernetesIngress`
  activo: reabre el robo de host #54), `NetworkPolicy`, `cert-manager.io/*`
  (ClusterIssuers usables desde cualquier namespace), Services NodePort.
  Apagar `kubernetesIngress` en `ingress/traefik/values.yaml`; alinear el
  AppProject del canario con el generador.
- **SC-5**: una sola identidad de registro (`aegis-dev`) push/pull/delete
  copiada a namespaces de inquilinos; imágenes `aegis-ci-*` sin escaneo ni
  firma y por tag mutable (el check 147 las exime). Identidades separadas en
  `lib/secrets.sh` y fase 40; `ci-images` escanea y firma como las bases;
  digests donde ya hay espejo.
- **K8-3**: k3s por `curl get.k3s.io | sh` sin fijar; clave apt de NVIDIA sin
  huella; actions por tag. Instalador descargado, sha256 fijado, ejecutado
  desde fichero; huella; actions por SHA.
- **SC-4**: `rbac.readSecrets: true` en Jenkins con jobs de inquilinos en
  `jenkins-system` con alcance a `cosign-signing-key`, `regcred-internal`,
  `cloudflare-api-token`; sin política de egreso para agentes.
- **K8-2**: PSS `restricted` solo en inquilinos, garage y ai; sin
  NetworkPolicy en registry-system, kyverno, cert-manager, infra-edge; k3s
  sin `--secrets-encryption`; sin firewall.
- **Deriva de versiones**: tofu 1.12.3 / 1.10.7 / «1.12.6»; alpine 3.21 /
  3.22; proveedor cloudflare `~>5.0` / `~>5.12`; muchas imágenes de plataforma
  por tag; kaniko v1.23.2. Unificar y un check de deriva.

### 4E — cambios de diseño (los tres críticos del informe; cada uno pide corrida)

- **SC-1 (C-1)**: ArgoCD construye TODAS las apps con
  `--enable-alpha-plugins --enable-exec` y la clave age privada montada en el
  mismo repo-server (`seed/platform/k8s/base/platform/argocd/values.yaml:11,47-60`):
  un push a un repo de inquilino puede ejecutar código junto a la clave que
  descifra todo. KSOPS como plugin CMP en sidecar que solo renderiza las
  Applications de plataforma que lo nombran (`plugin.name: ksops`); la clave
  solo en el sidecar; `kustomize.buildOptions` sin `--enable-exec`; fase 30 y
  `aegis org apply` ajustados. El experimento que lo demuestra está en
  `scratchpad/audit/13-exec-experiment.txt` de la sesión (kustomize 5.8.3).
- **SC-2 (C-2)**: el Jenkinsfile del inquilino corre `node ci/write-digest.mjs`
  (fichero del repo del inquilino) dentro de `withCredentials(github-token)`
  y ese token es el `gh auth token` del operador con scope `repo`
  (`Jenkinsfile.app:795-808`, `init/phases/15-third-parties.sh:662,830`).
  Credencial por repositorio (deploy key con escritura creada por `aegis app
  apply`) y el script ejecutado desde una copia de la plataforma.
- **C-3**: clave de firma y credencial del registro en el pod del inquilino
  (va con SC-4/SC-5).
- Lock de instancia (`flock` en `$AEGIS_HOME/.init-state/lock`) para init,
  update, rotate y timers; `NOPASSWD:ALL` permanente acotado a lo que el init
  usa; comprobación de arquitectura (solo amd64); `--non-interactive` aprueba
  todo lo rojo (responder «no» por defecto).

### 5 — cierre

Suite + `--harness` + todos los dientes en verde (`./bin/aegis verify
--teeth`, ~6 min ahora), `gitleaks dir` limpio, ningún nombre de máquina ni
persona en lo commiteado, push, y la propuesta de descripción/topics/release
del repo (no ejecutarla sin OK del mantenedor).

## 3. Qué validar en una instancia viva antes de llamar «hecho» a 4A

1. `aegis seed diff` y `aegis seed apply` (trae el wrapper de tofu nuevo);
   luego `aegis init --only 25` o `aegis destroy` sin `--yes` para ver
   `finish_state` en acción: nada de `terraform.tfstate*` queda en el env.
2. `aegis state backup` y `aegis state restore <bundle>` sobre una copia:
   aparece `~/aegis/.staging` (vacío al terminar); con un `.init-state/runs`
   grande, el mensaje «staging on disk under …».
3. `aegis data backup` de una organización: el dump ya no pasa por `/tmp`;
   `~/aegis/.staging` vacío al terminar; un `kill -TERM` a mitad deja nada.
4. `aegis init-log --only 05` (o cualquier fase corta): el dosier nace 0600
   en `runs/` 0700.
5. Un init completo (o `aegis rotate` de un secreto generado): con
   `inherit_errexit` un fallo latente dentro de un `$( )` ahora detiene la
   fase donde ocurre; si una fase se detiene en algo que antes «pasaba», ese
   es el punto a mirar, no a silenciar.
6. La fase 15 una vez (`aegis init --from 15` o un `--check`): los tokens
   se cifran en tmpfs y se mueven como ciphertext.

## 4. Dónde está lo que no se commiteó

El informe PDF (`INFORME-aegis-2026-10-13.pdf`), su `.md`, la evidencia
(`audit/`, 31 ficheros con SHA-256) y los borradores viven en el scratchpad de
la sesión que hizo esto, no en el repo, porque contienen hallazgos de seguridad
sin cerrar y el repositorio es público. El mantenedor los tiene descargados.
