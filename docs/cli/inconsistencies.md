# REGISTER OF INCONSISTENCIES — the rename of the CLI surface

**Raised on 2026-08-21**, by four parallel audits, BEFORE touching a
single line. It is an inventory, not a plan: the plan lives in
`cli/design.md` once it exists.

Every `file:line` coordinate below points into the **v2 tree**, which is
the tree that was audited. Where a name's language is the point being
made — the ten collisions, class F — the name is written as it stood
then, in Spanish. That is the evidence; rewriting it would destroy the
finding.

## The rule

**Nothing gets renamed if it is not on this list.** And the other way
round, which is the part that matters: **if something is not on the
list, it is not that it is fine — it is that nobody looked at it.** The
register gets crossed off in full or the rename is not done.

## The agreed scope

What gets renamed: command names, subcommands, flags, and every piece of
text a `--help` prints.

What is NOT touched: the contracts' vocabulary (`organizacion:`, `usa:`,
`cuota:`), the code's comments, the messages a command narrates while it
runs, nor the derived names in the cluster (`shop-cabeceras`,
`allow-api-a-internet`).

That trimming has a consequence that shows up in A3 and has to be read
carefully: **the day somebody translates the messages, there is an armed
bomb.**

## The numbers

| dimension | count |
|---|---|
| HARD dependencies (one command executes another) | 77 |
| Strings visible to the operator that name commands | ~155 (48 of high criticality) |
| Total raw mentions of the name | 452 |
| Confirmed cases of Disease E | 7 (5 full) |
| Commands in `platform/bin/` that any check verifies | **1 of 12** |
| Commands the seed carries | **3 of 12** |

---

# CLASS A — BREAKS IN SILENCE (Disease E)

The gravest part of the register. In every one of these cases the rename
**does not produce an error**: it produces a green or an amber that reads
as a normal state.

The pattern that generates them is always the same: **the code for "the
file is not there" (127, rc 2, `False`) collides with a code that was
already reserved for a legitimate, expected degradation.**

### A1 · `aegis-chequeo` stops measuring the edge and the webhooks, and says "no failures"

- **Where**: `platform/bin/aegis-chequeo:635` and `:654`
- **What happens**: it invokes `aegis-borde` and `aegis-webhook` by
  relative path, with no existence guard. It runs with `set -uo pipefail`
  **without errexit**, so a missing binary returns 127, and the
  `case $?` has no branch for 127: it falls into `*)` → `avisos++`.
  `fallos` never goes up → the final verdict prints **`sin fallos, N
  aviso(s)` and exits 0.**
- **What is lost**: the section that compares the declared hostnames
  against the ones that really exist in Cloudflare, and the one that
  verifies that a push reaches Jenkins. On 2026-08-05 that second one
  found that **two out of four repos had no webhook**.
- **Why it hurts**: the `*)` branch was written for the honest rc=2 of
  `aegis-borde` ("I could not talk to Cloudflare"). The rename injects a
  127 **disguised as rc=2**, indistinguishable from the expected
  degradation.
- **Fix**: an `[[ -x ... ]]` guard before invoking, or an explicit
  `127) mal "..." ;;` branch.
- [ ] pending

### A2 · Check 4 of `verify-static` passes exactly the same without measuring anything

- **Where**: `init/verify-static.sh:165`
  (`hay_generador = (P/"bin"/"aegis-org").is_file()`)
- **What happens**: if the file is not there, `hay_generador=False` →
  `StopIteration` → `por_contrato = {}` → the check prints an **identical
  PASS**, with one extra informational line that reads as "the seed is
  born with no organizations".
- **What is lost**: producer 2 in full (the reason the check was
  rewritten in #48), and the **only static consumer** of the generator's
  internal API — `gen.secrets_of`, `gen.repos_of`, `gen.orgs_with_bucket`.
- **The asymmetry that makes it poisonous**: if `aegis-org` exists but
  blows up on import → a correct `FAIL`. If it **does not exist** →
  silence. The "not there" path is treated as legitimate, and the rename
  makes it indistinguishable from "we moved it and nobody updated this".
- **Fix**: derive the generator's absence from the absence of
  `orgs/*.yaml`, not from the absence of the file. If there are
  contracts, the generator MUST exist.
- [ ] pending

### A3 · A freshly created webhook is reported as "already there" — **the message-layer bomb**

- **Where**: `platform/bin/aegis-app:713`
  (`creo = escribir and "webhook creado" in r.stdout`)
- **Producer of the string**: `platform/bin/aegis-webhook:182`
- **What happens**: `aegis-app aplicar` decides whether it converged or
  not **by grepping a Spanish literal** out of another command's stdout.
  If that message changes, `creo=False` and the table marks `ya estaba`
  instead of `hecho`. No exception, no different rc, no trace.
- **Why it is THE special case of this register**: it is the only one
  triggered by translating a **message**, not a name. Since we agreed to
  leave the messages in Spanish, **today it does not fire** — but it is
  left armed for the day somebody touches that layer. It is the argument
  for fixing it now, while we are here.
- **Its own comment says so** (`:710-713`), without knowing it is
  describing itself: *"Se lee del reporte del delegado — sus estados son
  estables"*. The rename is exactly the event that breaks that
  assumption.
- **Fix**: have `aegis-webhook` communicate the state by rc or by a
  machine-readable line (`STATE=created`), never by translatable prose.
- [ ] pending

### A4 · The rotation returns SUCCESS if the synchroniser is not there

- **Where**: `init/aegis-rotate.sh:757`
- **What happens**: `[[ -x "$PBIN/aegis-sync" ]] || { log_warn ...;
  return 0; }` — **`return 0` is success**. Rotating a credential without
  pushing the new Secret leaves the cluster with the old material.
- **The only trace** is a `log_warn` saying "sincronizá a mano", which
  reads as a routine instruction and not as "the mechanised step has
  disappeared".
- [ ] pending

### A5 · Two verifiers switch themselves off and the rotation is declared complete

- **Where**: `init/aegis-rotate.sh:243` and `:641`
  (`[[ -x "$PBIN/aegis-webhook" ]] || return 3`, same for
  `aegis-registro`)
- **What happens**: rc=3 means "NOT VERIFIABLE" and is well documented,
  but the consumer (`:1062-1065`) does `return 0` to its caller.
- **The worst part is the message**: it says *"NO HAY DIENTE que lo
  verifique. Escribí el verificador"* — **it actively attributes the
  wrong cause**. It sends you off to write a verifier that already
  exists, and the operator files it away as known debt while the
  rotation of the Jenkins HMAC and of the registry are declared done
  without ever having been verified.
- **Mitigating factor**: the `.done` marker is not written, so a trace is
  left on disk.
- [ ] pending

### A6 · The edge's CI job goes permanently AMBER with a false diagnosis

- **Where**: `platform/edge-chequeo/Jenkinsfile:117`
  (`python3 bin/aegis-borde`)
- **What happens**: with the file missing, `python3` exits with **rc 2** —
  which is precisely the code reserved for "could not be evaluated". The
  job goes `UNSTABLE` with the message *"falta credencial o Cloudflare no
  respondió"*.
- **Partial** because it is not green. But a recurring amber with a
  plausible external cause is exactly how a check stops being read.
- **The irony**: the comment immediately above (`:119-122`) names Disease
  E as its reason for existing.
- [ ] pending

### A7 · Check 86 degrades in silence if `aegis-init.conf` is touched

- **Where**: `init/verify-static.sh:2893-2906`
- **What happens**: if the conf is not there, the reinforcement that
  detects instance values leaked into the seed **disappears and the check
  passes anyway**, with a suffix on the PASS message.
- **Conditional**: `aegis-init.conf` is not in the rename's scope, but it
  is in the same blast radius as `aegis-init.sh`.
- [ ] pending

---

# CLASS B — TEXT CONTRACTS (sentinels that get parsed)

Literals that are not messages: they are **structure**. If the text and
its reader fall out of sync, the mechanism stops working without warning.

### B1 · The sentinel that avoids trampling manual edits

- **Where**: `platform/bin/aegis-org:1162`
  (`if "GENERADO POR \`aegis org\`" in viejo and ...`)
- **Written in**: the headers at `:355, 1721, 1838, 2008, 2135, 2160,
  2250`
- **What it protects**: it decides whether a generated file was edited by
  hand and must not be trampled. **If the header and the sentinel get
  renamed in different commits, the guard stops firing and we start
  trampling manual edits.**
- [ ] pending

### B2 · The marker that delimits the Jenkins jobs block

- **Where**: `platform/bin/aegis-org:2393`
  (`JOBS_BLOCK_START = "# --- DERIVADO por aegis-org (jobs de
  tenant)..."`)
- **Read in**: `platform/k8s/base/platform/jenkins/values.yaml:102,107`
- **What it protects**: it is a text contract between the generator and a
  versioned YAML. Without the marker, the derived block gets rewritten in
  the wrong place, or does not get rewritten at all.
- [ ] pending

### B3 · The literal "Resume:" that a check validates by exact text

- **Where**: `init/aegis-init.sh:212`, validated by
  `init/verify-static.sh:2171`
- **Double coupling**: a filename *inside* a printed message, which on
  top of that another file greps literally.
- [ ] pending

---

# CLASS C — HARD DEPENDENCIES (77) — they fail, but loudly

One command executes or imports another. These really do break; at least
they shout.

### C1 · The six `SourceFileLoader`s — **you have to grep TWO forms**

The module is loaded as `aegis_org` (**under**score) from the file
`aegis-org` (hyphen). A grep for one form does not find the other.

- `platform/bin/aegis-app:132-134`
- `platform/bin/aegis-borde:63-65`
- `platform/bin/aegis-secreto:516-518`
- `platform/bin/aegis-org-prueba:26-27`
- `platform/bin/aegis-tipos-prueba:29-30`
- `semilla/plataforma/bin/aegis-secreto:518`
- `semilla/plataforma/bin/aegis-tipos-prueba:30`
- [ ] pending

### C2 · Invocations assembled from a tuple or a variable (invisible to a simple grep)

- `platform/bin/aegis-app:513-516` — `["aegis-org", "aplicar", ruta]` and
  `["aegis-secreto", "--todos", ruta]` as **list elements**: the string
  `"bin/aegis-org aplicar"` does not exist anywhere.
- `platform/bin/aegis-app:100,704` —
  `WEBHOOK = os.path.join(AQUI, "aegis-webhook")`
- `init/aegis-rotate.sh:56` — `PBIN="$PLATFORM_DIR/bin"` and then
  `"$PBIN/aegis-webhook"`, `"$PBIN/aegis-registro"`, `"$PBIN/aegis-sync"`,
  `"$PBIN/aegis-chequeo"`. A `grep "platform/bin/aegis"` **does not see
  them**.
- `platform/bin/aegis-chequeo:635,654` —
  `$(dirname "${BASH_SOURCE[0]}")/aegis-borde`
- [ ] pending

### C3 · The only call from an init phase into `platform/bin/`

- **Where**: `init/phases/85-observabilidad.sh:298`
  (`bin/aegis-org borde`)
- **Failure mode**: it dies in phase 85 of a real run, **hours into the
  bootstrap**. And check 17 (*"the files the phases reference EXIST"*)
  **does not cover it**: its regex only looks at `ansible/...` and
  `$AEGIS_ROOT/init/...`.
- [ ] pending

### C4 · The rest of the hard ones

- `init/aegis-rotate.sh:751` → `aegis-init.sh --only <fase>`
- `init/aegis-rotate.sh:642` → `aegis-registro --revisar`
- `init/aegis-rotate.sh:1139` → `aegis-chequeo`
- `platform/edge-chequeo/Jenkinsfile:117` + `jenkins/values.yaml:275`
  (`scriptPath('edge-chequeo/Jenkinsfile')`)
- `init/verify-static.sh` — ~17 references by literal path and grep:
  `:397, 459-460, 969, 999, 1652, 1715-1717, 2028-2030, 2171, 2502-2517,
  2597-2620, 2628-2646, 2655-2668, 3067-3069`
- The 19 `source "$AEGIS_HOME/aegis.conf"` (13 phases + 6 more)
- [ ] pending

---

# CLASS D — ADJACENT NAME CONTRACTS

They are not the CLI, but they break if the rename drags them along — or
if it does NOT drag them along.

| # | contract | coupled with | risk |
|---|---|---|---|
| D1 | `.aegis-app/` (staging) in `platform/.gitignore:37` | `aegis-app` `STAGING_DIR`, and `aegis-org` uses the same | Renaming the dir without touching the ignore = **committing generated material** |
| D2 | glob `aegis-estado-*.age` | written by `init/aegis-backup.sh:51`, read by `aegis-chequeo:845` | The backup check finds nothing |
| D3 | glob `aegis-datos-org-<org>-*.age` | written by `aegis-respaldo:518`, read by `aegis-chequeo:883` | same |
| D4 | marker `.aegis-destino` | `aegis-respaldo:164` ↔ `aegis-chequeo:831` | |
| D5 | `/etc/sudoers.d/010-aegis-init-nopasswd` | `aegis-preflight.sh:31-32`, `lib/common.sh:737,739,755`, `phases/00-preflight.sh:60` | 5 places |
| D6 | the GitHub topic `aegis-app` | `aegis-app:106` | the repos already created carry it |
| D7 | `initiatedBy.username: "aegis-sync"` | `aegis-sync:56` | **it stays engraved in ArgoCD's history**; to be decided separately |
| D8 | `aegis-preflight.sh` copies itself into `$HOME` under a hardcoded name | `:169` and `:175` | **closed 2026-08-27**: the product lives in a repo, the copy is gone |
| D9 | The rule `("bin/aegis-org-prueba", ...)` in `bin/aegis-semilla:129` | `:252-256` `morir()` if it does not match | **Kills all three subcommands of `aegis-semilla`.** The rename's only loud failure — and it is a false positive |

- [ ] pending

---

# CLASS E — STRINGS TO THE OPERATOR (~155, of which 48 critical)

They break nothing. **They only misguide**, which in this house is
worse.

The 10 where a new user is left with no next move:

1. `init/aegis-init.sh:212` — `"Retomar: ... --profile ... --from ..."`.
   The only exit after a failed bootstrap phase. (And see B3.)
2. `platform/bin/aegis-app:573-578` — the **"siguientes pasos, EN ORDEN"**
   block. It is the complete handoff of provisioning an organization.
3. `platform/bin/aegis-org:1200` — `"se crean con: bin/aegis-secreto
   --todos"`. The code's comment says *"El comando exacto, no 'creá los
   secretos'"*.
4. `init/aegis-rotate.sh:1196-1199` — the closing of a rotation. Without
   this, the platform is left half-synchronised.
5. `init/aegis-rotate.sh:717,722` — the same, but mid-batch: the system's
   most fragile state.
6. `platform/bin/aegis-app:295` — diagnosis + remedy in a single string.
7. `lib/config.sh:184` — it blocks every unattended run.
8. `platform/bin/aegis-sync:31-32,59` — three in a 59-line file.
   `aegis-sync` is the command most cited by other commands.
9. `semilla/plataforma/orgs/README.md:11-14` — **the README that gets
   seeded into every new instance**. Four consecutive commands that die
   together.
10. `platform/bin/aegis-app:371` and `:556-557` — the two entry walls of
    the provisioning command.

- [ ] pending (the complete inventory is in the audits; 24 files)

---

# CLASS F — THE SEED

### F1 · It carries only 3 of the 12 commands

`semilla/plataforma/bin/` has `aegis-org`, `aegis-secreto`,
`aegis-tipos-prueba`. **The other 9 are missing.**

### F2 · Its `aegis-org` is behind and diverges in real content

124,690 B (live, 2026-08-21) against 105,042 B (seed, 2026-08-11) —
**444 lines of diff**. It is missing `USOS = {..., "internet"}`, the
whole block that derives the Jenkins jobs (`JOBS_BLOCK_START`), the CSP
headers, and the validation of `prompt` by class. **It is not
un-rendering: it is being behind.**

### F3 · `init/` is not part of the compared tree

There is no `semilla/init/`. `aegis-semilla` only compares `platform/` ↔
`semilla/plataforma/`. **A rename inside `init/` is detected by nobody
along this route** — and on top of that `verify-static.sh` measures the
SEED, not the instance.

### F4 · The failure shows up on another machine, not here

`semilla/plataforma/bin/aegis-tipos-prueba:30` loads `aegis-org` by name.
If the two trees fall out of sync, the test of the delivered artifact
blows up in **the bootstrap of a new instance**, not in the commit that
caused it. That is exactly the failure mode `aegis-semilla` exists to
prevent.

- [ ] pending

---

# CLASS G — DOCUMENTATION THAT GETS EXECUTED

Only the OPERATOR's is dangerous (somebody follows it step by step):

| file | blocks | note |
|---|---|---|
| `OPERAR.md` | 16 | **The guard's manual. The most dangerous file in the repo.** |
| `docs/protocols/organization.md` ×2 | 28 each | Byte-identical copies: double maintenance |
| `docs/protocols/rotation-checklist.md` ×2 | 2 | Followed item by item |
| `docs/protocols/rotate-age-key.md` ×2 | 34 | A ceremony executed literally |
| `docs/protocols/edge.md` | 8 | Only in `platform/`, does not travel to the seed |
| `semilla/plantillas/base/README.md` | 0 (7 mentions) | Read by whoever creates an app |
| `semilla/plataforma/orgs/README.md` | 4 | See E9 |
| `caminos/design.md` | 0 (24 mentions) | **It is the source of truth for the CLI's design** — renaming without touching it leaves the design lying |
| `AGENTS.md` | 6 | Instructions an agent executes |

Logbooks (`RUTA.md` 31 mentions, `PROGRESO.md`, `VALIDACION.md`,
`HISTORIA.md`): **not touched.** They are the historical record.

- [ ] pending

---

# CLASS H — ALREADY BROKEN TODAY (findings, not consequences)

The audit found these and they **exist before the rename**. Worth fixing
along the way.

| # | what | where |
|---|---|---|
| H1 | `aegis-rotate.sh` announces itself as **`aegis-rotar`**, a name that does not exist | `init/aegis-rotate.sh:1094` |
| H2 | The `.tf` files cite `aegis-rotate --verificar`, **without the `.sh`** | `tofu/modules/cloudflare-access/main.tf:29,30,43`, `grafana.tf:16`, `envs/cloudflare-tunnel/variables.tf:106` |
| H3 | The docs document **`aegis org rotar <org> <secreto>`**, a nonexistent subcommand | `docs/protocols/organization.md:342` |
| H4 | **35 generated files carry `aegis org` (the dispatcher form, which does not exist) AND `bin/aegis-org` in the same file** | banners in `k8s/organizations/*/`, `k8s/argocd-apps/tenants.yaml`, etc. |
| H5 | Three banner conventions alive at once | the 35 from H4 + `k8s/base/ai-system/{ruteo,registro,kustomization}.yaml` in lowercase |
| H6 | **The two acceptance tests are orphans**: nobody runs them, `verify-static` does not invoke them, there is no CI (`.github/` does not exist) | `aegis-org-prueba`, `aegis-tipos-prueba` |
| H7 | Check 15(a) matches itself against `'Bitwarden'` if `verify-static.sh` is renamed (the `--exclude` stops biting and `:439` is the only occurrence of the pattern in the tree) | `init/verify-static.sh:441` |

- [ ] pending

---

# ABSENT COVERAGE — what nothing verifies

This is not an inconsistency: it is the hole all the others come in
through.

1. **No check verifies the existence of 11 of the 12 commands in
   `platform/bin/`.** The only reference in the 91 checks is check 4 →
   `aegis-org`, and that check IS case A2. **Moving the other 11 to the
   dispatcher is invisible: the suite comes out `ALL PASS`.**
2. `verify-static.sh` points at `semilla/plataforma`, not at
   `platform/`.
3. Check 17 does not reach `bin/aegis-org borde` in phase 85 (see C3).
4. There is no CI: `.github/` does not exist. Nothing runs on its own.

**Mandatory counterpart of the rename**: a new check that demands every
declared command exists, is executable and declares its `summary` and its
`group`. Without that, the dispatcher adds one more layer where something
can go missing in silence.

---

# MAP OF THE LANGUAGE MIX (reference, not action)

The repo **is already bilingual** and nobody had mapped it. The cut is
almost clean by tree: **`init/` leans English, `platform/bin/` leans
Spanish**, with `aegis-rotate.sh` and `aegis-app` as the exceptions that
break the rule.

### The ten same-concept-two-language collisions

1. **"check" has four forms**: `aegis-chequeo`, `--check`, `--revisar`,
   `--verificar`, plus `verify-static.sh` and `edge-chequeo/`. And
   `aegis-rotate.sh` uses `--revisar` **and** `--verificar` in the same
   script for two different things that in English would both be *check*.
2. **"edge" vs "borde"**: `edge.yaml` (EN) is read by `bin/aegis-borde`
   (ES); namespace `infra-edge` (EN), dashboard `borde.yaml` (ES),
   `docs/protocols/edge.md` (EN), and `platform/edge-chequeo/` which is
   **English-hyphen-Spanish inside a single identifier**.
3. **"backup" vs "respaldo"**: `init/aegis-backup.sh` (EN) **invokes**
   `bin/aegis-respaldo` (ES). `OPERAR.md:269` explains them together.
4. **"rotate" vs "rotar"**: `aegis-rotate.sh` (EN) with the flags
   `--rotar`, `--revisar`, `--verificar`, `--continuar` (ES). The most
   grating case.
5. **"canary" vs "canario"**: `semilla/canario/` (ES) generates
   `org-canary` (EN).
6. **"template" vs "plantilla"**: `semilla/plantillas/` (ES) vs
   `docs/protocols/templates/` (EN); flag `--plantilla` (ES).
7. **"tenant" vs "organización"**: the same object depending on the layer
   — `orgs/`/`org-shop` vs `aegis-tenant-shop`/`aegis-tenants` vs
   `aegis-organizaciones`. And `allow-tenants-a-gateway` is
   **English-Spanish-English inside a single resource name**.
8. **`platform/` (EN) and `semilla/plataforma/` (ES) are the same
   tree.**
9. **"routing"**: everything is `ruteo` (ES) and it generates
   `IngressRoute` (EN) objects.
10. **`ai stop` and `ai cerrar` are aliases of the same command in two
    languages.**

### Sibling files in two languages

- The three master contracts: `edge.yaml` (EN), `planes.yaml` (ES),
  `servicios.yaml` (ES).
- The four dashboards: `bootstrap.yaml` + `supply-chain.yaml` (EN)
  alongside `borde.yaml` + `plataforma.yaml` (ES).
- The fourteen init phases: all EN except `85-observabilidad.sh` and
  `15-terceros.sh`.
- The four organization contracts: `blog`/`shop` (EN),
  `ejemplo`/`portafolio` (ES).
- Three engines: `engine-cpu`, `engine-llm` (EN), `engine-charla` (ES).

### Command names

**12 English** · **6 Spanish** (`aegis-borde`, `aegis-chequeo`,
`aegis-registro`, `aegis-respaldo`, `aegis-secreto`, `aegis-semilla`) ·
**2 hybrids** (`aegis-org-prueba`, `aegis-tipos-prueba`).

A curious note: **`registro` means two different concepts in the repo**
(`aegis-registro` = the image registry; `ai-system/registro.yaml` = the
catalogue of AI tasks), and neither matches its namespace, which is
`registry-system`.

### Flags

- **English**: `--check`, `--force`, `--help`, `--yes`, `--only`,
  `--from`, `--list`, `--org`, `--profile`, `--configure`,
  `--non-interactive`, `--reset-state`, `--purge-secrets`, `--stdin`,
  `--with-charts`
- **Spanish**: `--todos`, `--rotar`, `--revisar`, `--verificar`,
  `--continuar`, `--capturar`, `--listar`, `--restaurar`, `--reubicar`,
  `--aplicar`, `--plantilla`, `--hasta`, `--fuera-de-linea`, `--a`

`aegis-app` has `--plantilla` (ES) and `--check` (EN) **in the same
command**. `ai` has `--force` (EN) and `--hasta` (ES) in the same `case`.

---

## Suggested order of attack

1. **Class A first, BEFORE renaming anything.** Fixing the seven cases of
   Disease E turns the rename into a noisy operation: anything we break
   is going to shout. Doing it the other way round is renaming blind.
2. **The absent coverage**, in the same movement: the check that demands
   every command exists and declares itself.
3. Class B (the sentinels) — header and reader in the **same commit**.
4. Classes C and D — the rename proper.
5. Classes E and G — strings and operator documentation.
6. Class F — the seed, which also drags along the F2 debt that already
   existed.
7. Class H — along the way, because it is already broken.
