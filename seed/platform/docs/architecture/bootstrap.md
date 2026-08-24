# bootstrap.md — LA fuente canónica de la secuencia de aegis v2

Reemplaza al overview §8-9 de v1 (que quedó desactualizado vs
ADR-0011/0015/0003 — drift que ADR-0011:123 dejó como TODO). Si
este documento y el init divergen, ES UN BUG: se corrigen juntos.

## Identidad

aegis-init ≡ task #56 ≡ DR Nivel 3 ≡ bootstrap Hetzner. UN
artefacto, perfiles: greenfield (v1 completo) | hetzner (deltas) |
re-bootstrap (NO implementado — límite conocido, ver §Límites).

## La secuencia (14 fases, init/phases/)

```
00 preflight      config GUIADA (wizard: pregunta+valida+escribe;
                  jamás "completá este archivo") + límites +
                  precondiciones verificadas
05 host           instala userland Linux PINNEADO; VERIFICA lado
                  Windows (checklist accionable, no automatiza)
10 age-ceremony   genera la raíz de confianza; 3 resguardos
                  VALIDADOS por roundtrip; .envrc/direnv; .sops.yaml
12 workrepos      CREA y SIEMBRA los repos de trabajo DESECHABLES
                  (ops-stack-v2 / hello-aegis-v2 por default) vía
                  gh, idempotente con marcador topic; settings B4
                  por gh api; known_hosts desde los pins T1
15 terceros       AUTOMÁTICOS (D11): UNA maestra CF efímera →
                  tokens acotados acuñados por API; deploy keys
                  registradas por gh; 2 webhooks por gh api;
                  credencial CI = gh token (la GitHub App fue
                  REEMPLAZADA — crear una sin navegador no existe);
                  cifra 8 Secrets + tokens
20 k3s            ansible: kernel+k3s pinneado; [hetzner: Cilium
                  ANTES de toda NetPol]; storageclass; kubeconfig
                  VERIFICADO (el bache del cluster ajeno)
25 edge-tofu      tofu SOLO Cloudflare (D10): tunnel + CNAMEs;
                  TUNNEL_TOKEN → Secret KSOPS sin pantalla;
                  commit+push de cifrados
30 argocd         LA única instalación imperativa: Secrets de
                  bootstrap por KUBECTL (D2: age jamás en un
                  state) + helm install (mismos values que la App)
35 gitops         root + syncs EN ORDEN: argocd-secrets → argocd
                  (ADR-0015) → cert-manager → PKI → issuers →
                  traefik → cloudflared; gate edge end-to-end
40 registry-pki   htpasswd + 4 regcred ATÓMICOS (un proceso);
                  registry con TLS DESDE EL DÍA UNO; CA al host
                  por role Ansible (por nodo)
50 jenkins        admin random; secrets→chart (orden); JOBS-AS-
                  CODE de nacimiento (PVC descartable); job
                  ci-images buildea el tooling (ya no manual)
60 webhook        completa URL de la App; gate e2e: push REAL →
                  build REAL
70 deploy-auto    tenant patrón A; canary con pull real (EL gate
                  del camino registry→kubelet); ANTI-LOOP PROBADO
                  ANTES del write-back; IU dry-run → gate → flip
80 supply-chain   trivy server; CEREMONIA cosign; PRIMERA IMAGEN
                  FIRMADA; kyverno; kyverno-policies AL FINAL
                  (D5 — Enforce sin firma previa se rechaza solo);
                  gate final: positivo mutado a digest + negativo
                  rechazado + scope respetado
```

Orden de sync = mecanismo (no hay sync-waves): root es MANUAL
(ADR-0012) y el init decide el cuándo de cada App. Regla general:
toda App *-secrets ANTES de su consumidor.

## Decisiones v2 vs v1 (cada una con su porqué)

- **D6 — tofu sin K8s**: v1 instaló cert-manager/traefik/argocd por
  tofu-helm (ADR-0011) y después pagó Mitad B entera para
  transferirlos a GitOps (removed blocks, adopción). v2 no crea esa
  deuda: helm install SOLO para argocd, GitOps para todo lo demás.
  El tfstate queda sin UN SOLO secreto de cluster. Desvío
  consciente de ADR-0011 — el problema que ADR-0011 resolvía
  (circularidad) solo existía para argocd mismo.
- **D2/D3 — secretos**: age/deploy keys por kubectl, jamás provider;
  pausas humanas agrupadas (fase 15); derivaciones atómicas
  estructurales (lib/secrets.sh); ceremonias con roundtrip para
  irreemplazables. Modelo: random+Bitwarden principal, manual
  doble-tipeo como excepción (veredictos 20.2/20.3 del reporte).
- **D5 — H-7 codificado**: kyverno-policies última, tras primera
  firma.
- **D9 — jobs-as-code de nacimiento**: el PVC de Jenkins es
  descartable; los jobs viven en JCasC job-dsl (sintaxis verificada
  en v1 3.B.3).
- **B4 corregido de raíz**: delete_branch_on_merge=false en env Y
  default del módulo.
- **TLS del registry desde el día uno** (2026-07-04:7).
- **Role Ansible registry-host-trust**: el bloque sudo manual de v1
  (2026-07-02:132) es playbook por-nodo.
- **D10 — GitHub fuera de tofu; repos de trabajo del init**: los
  repos que el init usa son PROPIOS y DESECHABLES (creados y
  sembrados por la fase 12 con marcador `aegis-v2-disposable`) —
  jamás los repos reales del v1 (el init les ESCRIBE: commits,
  tags, settings, webhooks, write-back del IU). Con los repos
  pre-creados por gh, el env tofu github-repos solo aportaba state
  + PAT + problema de import: settings y webhook van por gh api
  idempotente (secret por --input, nunca argv), el PAT se ELIMINÓ
  del flujo (la credencial es la sesión gh del operador) y tofu
  queda Cloudflare-only (1 TF_VAR). Corrige además el bug de
  secuencia: las deploy keys de la fase 15 se registran contra
  repos que ahora ya existen.
- **Config guiada (misión del operador)**: wizard interactivo en
  fase 00 — explicación + default inferido + validación por campo,
  y el init ESCRIBE el .conf. Un .conf pre-hecho se respeta
  (re-corridas/automatización). Mismo principio que los secretos:
  el init pregunta y hace; el operador decide y confirma.
- **D11 — automatización total (rediseño post-corrida #2)**: la
  fricción manual NO es seguridad. CERO navegador, CERO archivos
  movidos a mano, CERO tokens creados en paneles, prompts
  agnósticos (el init no asume gestor de secretos). Piezas:
  (a) GitHub App REEMPLAZADA por el token de la sesión gh como
  credencial de scan — crearla headless NO EXISTE (manifest flow =
  redirect web) y acuñar PATs por API tampoco; trade-off y upgrade
  path en docs/protocols/github-credential.md. (b) Cloudflare: una
  credencial MAESTRA efímera (vive solo en tmpfs durante la fase
  15) acuña los 2 tokens acotados vía API (permission groups
  matcheados POR NOMBRE contra la lista viva) y se destruye con
  shred. (c) Deploy keys registradas con `gh repo deploy-key add`.
  (d) STORE de estado cifrado (init/.state-secrets/, age): todo
  secreto generado se persiste y los --from REUTILIZAN en vez de
  regenerar — muere el ciclo de credenciales huérfanas. (e) El
  ÚNICO acto humano irreducible: resguardar la age key (todo lo
  demás se recupera con ella); la ceremonia cosign desapareció.
  (f) El orquestador RE-DERIVA el entorno (SOPS_AGE_KEY_FILE,
  AGE_PUBLIC) antes de cada fase — ninguna fase depende del export
  de otra (la familia de bugs de estado de la corrida #2).

## Límites conocidos (v1 del init)

0. Los repos de trabajo (ops-stack-v2 / hello-aegis-v2) son DE
   PRUEBA y DESECHABLES: el init y la plataforma les escriben
   libremente. Promover el resultado a "producción" es una decisión
   posterior del operador (renombrar/limpiar/re-bootstrap), fuera
   del alcance de este init.
1. Pérdida total de GitHub: sin camino (arranca con clone). H4.
2. Re-bootstrap con import de recursos CF/GitHub vivos: sin
   procedimiento (greenfield RECREA). H5.
3. Lado Windows: checklist verificada, no automatizada.
4. Recrear el tunnel puede dejar residuos DNS del anterior
   (comportamiento sin fuente — DOCUMENTAR el resultado en la
   primera validación).
5. Los gates de fail-closed con force-kill (crash duro de Kyverno)
   son de la VALIDACIÓN, no de cada bootstrap (disruptivos).
6. Tiempo total: NO se promete "~1 h" hasta medirlo (el dato lo
   emite el propio init — observability/design.md §1).

## Validación (≡ cerrar task #56)

Correr el perfil greenfield COMPLETO en entorno virgen — construir
y validar son UN hito. Candidatos de entorno (decisión abierta del
operador): instancia WSL2 importada limpia (fiel al host local) /
VM Hetzner (fiel al perfil hetzner). Cada perfil se valida en su
terreno.
