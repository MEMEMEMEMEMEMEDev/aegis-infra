# Glossary — the words this codebase uses

aegis is written in **English**: identifiers, comments, messages, the
seed, the docs. This file is the authority on which English word stands
for which idea, and it exists for one reason, taken verbatim from the
CLI design: **one concept, one language, one name.**

That rule is not a preference. The v2 audit found ten same-concept
two-name collisions — `edge`/`borde`, `backup`/`respaldo`,
`rotate`/`rotar`, `canary`/`canario`, `template`/`plantilla`,
`tenant`/`organización` — and each one cost somebody an afternoon. A
glossary that lives in a file can be checked; one that lives in a head
cannot.

---

## 1. The domain

| Word | Means |
|---|---|
| **product** | this repository: `bin/ libexec/ lib/ init/ verify/ seed/`. Read-only during a run. `AEGIS_ROOT`. |
| **instance** | one machine's living state: `platform/ .init-state/ .state-secrets/ aegis.conf`. Mutable. `AEGIS_HOME`. |
| **artifact** | the seed as a thing that gets verified — what `aegis verify` measures. |
| **seed** | `seed/`: what ships. Platform manifests, templates, canary. Carries placeholders, never values. |
| **platform** | `seed/platform/`: the GitOps repo the installer deploys. |
| **template** | `seed/templates/`: skeletons instantiated into a real app repo. A template **evaporates** once instantiated; the contract is the only surviving truth. |
| **canary** | `seed/canary/`: the smallest possible tenant, used to prove the whole path works. |
| **contract** | one org's `orgs/<name>.yaml`. The single source every derivation reads. |
| **org** | a tenant. One namespace, one quota, one set of services. |
| **phase** | one numbered, idempotent step of `aegis init`. |
| **gate** | a measured assertion inside a phase. Records to `gates.jsonl`. |
| **check** | one file in `verify/checks/`. Exactly one verdict. |
| **tooth** (pl. **teeth**) | `verify/teeth/NNN.sh`: mutations that must turn a check red (`red_k`) and legitimate changes that must keep it green (`control_k`). A check without a biting tooth is a promise without proof. |
| **dossier** | the per-run record: `runs/<id>/` with `meta.json`, `init.log`, `gates.jsonl`, `phases.tsv`. |
| **edge** | whatever brings outside traffic in: the Cloudflare tunnel, or the local systemd bridge. |
| **round** | one pass of `aegis check` over a live instance. |
| **run** | one execution of `aegis init`. |
| **profile** | which edge shape a run assumes: `cloudflare` or `local`. |
| **marker** / **sentinel** | the strings that mark generated files. They live in exactly one module. |
| **placeholder** | `__LIKE_THIS__` in the seed. Rendered by a phase, never committed rendered. |

## 2. The three outcomes

Every command, every gate, every check resolves to exactly one of these
and says which. The whole project exists because a fourth possibility —
**silence** — used to be indistinguishable from success.

| State | rc | Means |
|---|---|---|
| `done` | 0 | it was made so, now |
| `already` | 0 | it was already so; nothing was done and nothing is wrong |
| `wrong` | 1 | it is missing, or it is not as declared |
| `not-evaluable` | 2 | **the instrument never reached the subject.** Not a pass. Not a failure. |
| — | 3 | invalid usage, or a bug in the verifier itself |

`not-evaluable` is the load-bearing one. "I could not measure" outweighs
"it is wrong", because a wrong answer sends you to fix something and a
silent non-measurement sends you nowhere.

## 3. Retired words — enforced

Every term in this table is **gone from the code**, and `aegis verify`
refuses to let it back (check 111). Moving a row into this table is what
makes a rename permanent; adding one before the term is actually gone
turns the verifier red, which is exactly the point.

The check reads non-comment lines only. A comment or a document may
still name a retired word when it is *narrating history* — several do,
and that narration is the most valuable thing in this codebase.

| Was | Is | Note |
|---|---|---|
| `rutas.py` | `paths.py` | the module. `rutas` in the *routing* sense is `routes` — a real homonym, and the reason this row says which one. |
| `marcas.py` | `markers.py` | |
| `desenlaces.py` | `outcomes.py` | |
| `codigos-de-salida.txt` | `exit-codes.txt` | |
| `planes.yaml` | `plans.yaml` | |
| `servicios.yaml` | `services.yaml` | |
| `tareas.yaml` | `tasks.yaml` | |
| `contrato.yaml.tpl` | `contract.yaml.tpl` | |
| `escribir-digest.mjs` | `write-digest.mjs` | |
| `ntfy-puente` | `ntfy-bridge` | |
| `dominio_raiz` | `root_domain` | contract and edge key |
| `equivalencia-org.sh` | `org-equivalence.sh` | |
| `desenlaces`/`Pasos.paso` | `outcomes`/`Steps.step` | and the state VALUES with them: `hecho`→`done`, `ya-estaba`→`already`, `mal`→`wrong`, `no-evaluable`→`not-evaluable`. These are the machine-readable contract in `gates.jsonl`, so producers and consumers moved together. |
| `NoSePudo` | `CouldNotEvaluate` | |
| `RC_USO` | `RC_USAGE` | |
| `CABECERA` | `HEADER` | |
| `MARCO` | `FRAME` | now computed, not hand-drawn: the box width follows the text, so a translation cannot silently break the alignment |
| `FIRMA_GENERADO` | `GENERATED_SIGNATURE` | |
| `PREFIJO_HASH` | `HASH_PREFIX` | |
| `es_generado` | `is_generated` | |
| `sin_hash` | `without_hash` | |
| `MARCA_JOBS_INI` | `JOBS_BLOCK_START` | and `_FIN`→`_END`, `MARCA_SONDAS_*`→`PROBES_BLOCK_*` |
| `PATRON_BLOQUE_JOBS` | `JOBS_BLOCK_PATTERN` | |
| `PREFIJO_RETOME` | `RESUME_PREFIX` | the literal moved too: `Retomar:` → `Resume:` |
| `FIN DERIVADO` | `END DERIVED` | |
| `# titulo:` | `# title:` | the metadata line every check carries |
| `rojo_N` | `red_N` | the tooth prefix — and the tooth's *kind* string with it, which is what `"${kind}_$k"` builds |
| `FASES` | `PHASES` | |
| `numero_de` / `titulo_de` | `number_of` / `title_of` | |
| `correr_check` / `correr_dientes` / `correr_harness` | `run_check` / `run_teeth` / `run_harness` | |
| `_diente_uno` | `_one_tooth` | |
| `perfil_actual` / `hay_perfil_local` | `current_profile` / `has_local_profile` | |
| `seleccion` | `selection` | |
| `FALLOS` / `PASOS` / `SALTOS` | `FAILURES` / `PASSED` / `SKIPPED` | |
| `TRABAJOS` / `LISTA_PERFILES` / `AVISO_PERFIL` | `JOBS_LIST` / `PROFILE_LIST` / `PROFILE_NOTICE` | |
| `es_local` | `is_local` | and `perfil()` → `profile()` |
| `PARECIDOS` | `SIMILAR` | |
| `canario` | `canary` | |
| `edge_origen_responde` | `edge_origin_responds` | the probe that phases 35, 60 and 85 use — and check 090's load-bearing `grep -v` anchor moved with it |

## 3b. Being retired — in progress

These are decided but unfinished: the file and directory names have
moved, and the Spanish word survives in prose that has not been
rewritten yet. Each row graduates to §3 when the code stops containing
it — and not one commit before, because a ratchet that lies is worse
than no ratchet at all.

| Was | Is |
|---|---|
| `semilla` | `seed` |
| `plantilla` | `template` |
| `plataforma` | `platform` |
| `ruteo` | `routes` |
| `observabilidad` | `observability` |
| `reglas` | `rules` |
| `eventos` | `events` |
| `borde` in a dashboard filename | `edge` |
| `consumo` in a dashboard filename | `usage` |
| `bin/aegis-org` (the v2 path) | `aegis org` |
| `aegis-org aplicar` | `aegis org apply` |
| `aegis-app nueva … --plantilla` | `aegis app new` |
| `plan-borrar` · `borrar` · `migrar --a` | `plan-delete` · `delete` · `migrate --to` |

Four of these rows are COMMAND FORMS, not file names, and they are the
ones that rot in silence: `bin/aegis-org aplicar` names both a path
that no longer exists (the code lives in `libexec/`, reached through
the dispatcher) and a subcommand that was renamed. Check 106 does not
see them — it validates citations of the form `aegis <cmd> <sub>`, and
these carry neither the `aegis ` prefix nor an existing subcommand. On
2026-08-25 there were 20 of them across `seed/`, every one inside
prose. They come out with the translation, and only then do they
graduate to §3.

## 4. Rules for new names

1. **A name is derived, not repeated.** If two places must agree on a
   string, it lives in one module and both import it.
2. **Never two names for one concept**, and never one name for two
   concepts inside one scope. If a Spanish word was genuinely two things
   (`rutas`), the glossary says which English word each becomes.
3. **Say the outcome, not the feeling.** `not-evaluable`, not `unknown`.
   `already`, not `ok`.
4. **The message names the command by deriving it from `argv[0]`**,
   never as a literal. Renaming the binary must not orphan the prose.
5. **Prose in `plan/`, `ENCARGO.md` and `EJECUTADO.md` stays Spanish.**
   Those are the working record between the operator and Claude, not the
   product. Everything a stranger can touch is English.

## 5. Pending coordinated renames — the inventory

Everything below is STILL SPANISH ON PURPOSE, and every row was left
that way during the 2026-08-25 translation because moving it alone
breaks something. This is not a wish list: it is the map for the day
these move, and each entry names who compares it. Nothing here is a
§3 row yet — a word graduates to §3 only once it is gone from the
code, and none of these are.

It is split in TWO inventories, and the split is the point. §5A is
renames of CODE: a check sees them, `git revert` undoes them, the worst
case is a loud red. They go through the ratchet of §3b → §3. §5B is
renames of LIVE OBJECTS and ON-DISK FORMATS: no check sees them, git
does not undo them, and they break things that already exist. Those
are not translation — they are migration, and they belong to the
teardown-and-rebuild (T-06/T-08), not to a language pass. Until
2026-08-26 the two were one list, and a reader could not tell a
one-commit rename from a change that orphans every tenant's
Application.

The instrument was corrected the same day: check 111 now matches WHOLE
words. Under the old substring match, retiring `usa` flagged `usage`,
retiring `organizacion` flagged `aegis-organizaciones`, and the first
group below could not even begin.

### 5A. Renames of code — through the ratchet

#### 1. The contract's vocabulary — the most expensive

The keys, as `_only()` in `lib/aegis/org.py` accepts them (measured
2026-08-26, six call sites): contract = `version organizacion dominio
cuota repo almacenamiento ai servicios`; `almacenamiento.bucket`;
`ai.plan` and `ai.tareas[]` = `nombre capacidad prompt`; `servicios[]`
= `nombre tipo repo puerto publico usa`. And the values
`pequena|mediana|grande`, `basico|estandar|intensivo`,
`estatico|http|postgres|worker`. (`ai`, `plan`, `prompt` and `repo`
are already English: nothing to move.)

498 occurrences in 26 files. Moves together, in ONE commit:

- `lib/aegis/org.py` — `_only()` REJECTS unknown keys, so a
  half-rename does not degrade: it refuses every contract. Three
  sites inside the file are NOT the contract key and a blind
  substitution breaks them silently: the Prometheus label
  `organizacion` on the tenant probes (`org.py:2599`, consumed by
  `vmalert-rules.yaml:210`); the `registro.json` keys `capacidad` and
  `tareas` read by the AI gateway, which does not travel in the seed;
  and `module: [sitio_publico]`, which check 092 reads as text.
- `seed/platform/services.yaml:77` — `puerto: 5432` under
  `tipos.postgres`, read as `t['puerto']` in `org.py:539,574`.
  **Missing from this inventory until 2026-08-26**: renaming `puerto`
  without it makes `aegis org apply` die with `KeyError` while
  rendering postgres.
- `seed/platform/plans.yaml` (`cuota:` and the six plan names),
  `seed/templates/base/contract.yaml.tpl` (check 055 greps
  `publico:` in it), `seed/platform/orgs/README.md`.
- `libexec/dev/test-types` — 52 lines, coupled TWICE: the YAML
  fragments carry the keys, and the third field of every tuple is the
  literal error text of `org.py`. No safe order: same commit.
- `libexec/aegis-{app,check,data,secret}` — read the keys. In
  `aegis-data`, ONLY `sources()` (lines 258–265) is contract; the
  other 19 hits are the bundle manifest and belong to §5B.
- checks 055, 091b (its synthetic contract) and 106.

NOT in this group, contrary to what this section said before
2026-08-26: check 004 has zero hits (its `ai` is a path), and
`init/phases/85` has zero (its `publico` is the gate
`obs-ntfy-publico-responde`, group 5).

This is the only rename in the whole product where a mistake leaves
the product unable to read its own contract.

#### 2. The AI configuration's vocabulary

`capacidades` `proveedor` `modelo` `contexto_max` `clases` `tareas`
`peso` in `seed/platform/ai/{routes,tasks}.yaml`, plus the capability
names `chat.rapido` `chat.largo` `traduccion` `transcripcion` and the
file `docs/architecture/capacidad-ai.md` (linked by name from
`attach-ai-subsystem.md`). Read by `org.py` at load time. The values
also leave the product as `ruteo.json`/`registro.json` toward the AI
gateway, which is declared absent from the seed: that is the one
place in this group no check can see.

#### 3. Names emitted into the cluster — the ones that are code

| Name | Who compares it |
|---|---|
| `{org}-cabeceras` · `-ritmo` · `-cuerpo` · `-ruteo` | check 091 (twice), 091b, `org.py`, org-canary's hand copies |
| `aegis.dev/component: datos` | `libexec/aegis-data:264` selects by it |
| `aegis.dev/rol: aprovisionar-bucket` | garage's netpol ↔ `org.py` |
| `secret-{n}-credenciales`, key `usuario` | `org.py`, `aegis secret` — moves with the NEXT rotation, since the live Secret carries the key |
| `ai-registro`/`registro.json`, `ai-ruteo`/`ruteo.json` | `org.py`, the gateway |
| `aprovisionar-bucket.mjs` → mounted as `aprovisionar.mjs` | `org.py` (3 places), the equivalence harness |
| `medir-y-pushear` (container) | `trivy-db-age.yaml` |
| `desplegar` (Jenkins stage) | `org.py:725`, `init/phases/70:149` — nothing compares a stage name, so a rename fails silently |

#### 4. Observability — the ones that are code

The 17 alert names (`DeadmanAegis`, `TunelSinConexion`,
`SitioDeInquilinoCaido`, `InquilinoAlLimiteDeMemoria`,
`TargetDeScrapeCaido`, `JobDeScrapeDesaparecido`,
`KyvernoAdmisionRechazadaEnTenant`, `ImagenSinEscaneo`,
`ImagenSinFirma`, `TrivyDBVieja`, `TrivyDBSinMedida`,
`RegistryCertServidoPorExpirar`, `RegistryProbeFalla`,
`TrivyHealthzFalla`, `BlackboxSinMedida`, `TunelSinScrape`,
`SitioDeInquilinoSinSonda`) — check 092 holds six of them in a
`NO_GUARD` table and cross-checks BOTH directions, and since
2026-08-26 its §10 names the absence of `JobDeScrapeDesaparecido`
instead of comparing nothing; 087 and `libexec/dev/seed` name others.

The blackbox module `sitio_publico` and the derived `job_name:
sitio-{org}` — check 092 reads them OUT OF `org.py` as text.

Dashboard uids `aegis-plataforma` and `aegis-consumo`, the ConfigMap
data keys `borde.json` · `plataforma.json` · `consumo.json` and the
ConfigMap names `dashboard-borde` · `dashboard-plataforma` ·
`dashboard-consumo`. The FILENAMES are already English; the identities
inside are not. Nothing in `verify/` compares them.

Vector's component ids (`marca_tiempo`, `metricas_propias`, `eventos`,
`eventos_json`, `metricas`, `vlogs_eventos`) and the field
`ts_colector`, which is also hardcoded in a sink URI
(`_time_field=ts_colector`) — wired together by `inputs:`, so renaming
one alone silently detaches a pipeline stage. Nothing in `verify/`
compares them either.

#### 5. The init's gates

Roughly half of the gate names are Spanish, and around thirty of them
are grepped by a check. (The exact denominators vary with how the
gates built from variables — `instalado-$x`, `kyverno-restart-$x` —
are counted; two independent surveys gave 76/134 and 65/138.) They
land in `gates.jsonl` and the bootstrap dashboard reads them.
Examples: `nodos-ready`, `reloj-sin-skew`, `host-confia-en-el-CA`,
`los-6-secrets`, `clusterip-coincide-con-el-service`,
`obs-ntfy-publico-responde`.

Every check that greps a gate name does it in the safe form
(`grep -q 'X' || D=...`): a renamed gate turns the check RED, not
blind. Two are singled out because a check compares more than the
string: `clusterip-coincide-con-el-service` (check 070 and its tooth)
and the ansible task `coredns EXISTA` (check 071 compares the LINE
ORDER around it, so even moving it up a line turns it red).

This block was invisible to every measurement made during the
translation, and the reason is worth writing down: the survey looked
for Spanish FUNCTION WORDS (`que`, `para`, `del`…), and an identifier
like `nodos-ready` contains none. The 2026-08-26 survey with a lexicon
detector counts 442 Spanish-signal lines in 67 files of `seed/`, 170
of them carrying a term this section does not list. A measurement of
«how much is left» that only counts prose reports zero while a third
of the product's vocabulary is still in the other language.

#### 6. Small ones with no dependencies

`VERIFICAR-ANTES-DE-HETZNER` (check 012a and its tooth) ·
`item.clave`/`item.valor` in ansible's bootstrap-host loop (both sides
or neither) · `CLARO`, `CIFRADO`, `HUELLA_ANTES`, `huella()` in
`tofu-apply.sh` (nothing outside that file names them) · the `aegis
vps entregar` subcommand · `transcripcion` in the pending-capabilities
list.

### 5B. Live objects and on-disk formats — migration, not translation

None of these can be verified by a check, reverted by git, or moved in
a commit. Each one changes the meaning of something that already
exists outside the repository. They move during the teardown and
rebuild (T-06 → T-08), where the old object is destroyed and the new
one born, or they do not move at all.

| Name | What renaming it does to the LIVE instance |
|---|---|
| `aegis-organizaciones` (AppProject) | orphans the Application of every tenant: ArgoCD refuses an app whose project does not exist. Also in `appprojects.yaml`, `org.py`, `libexec/aegis-check:786` |
| `vmalert-reglas` (ConfigMap) | vmalert keeps running with NO rules until it is restarted against the new name. `vmalert/values.yaml`, `libexec/aegis-check:1176` |
| `operador` · `puente` (ntfy identities) | they are real credentials the bridge authenticates with; renaming means a rotation, not an edit |
| `aegis-alertas` (ntfy topic) | every subscribed phone stops receiving |
| `"origen"` in the `AEGIS_EVENT` JSON of `mirror-images/Jenkinsfile` | a log contract already ingested into vlogs-events: changes the meaning of a year of records retroactively |
| **the backup format** — `MANIFIESTO.json`, `.aegis-destino`, and ~30 JSON keys (`nombre`, `archivo`, `tablas`, `bases`, `objetos`…) in `libexec/aegis-data` | makes every `.age` bundle already written UNREADABLE by `list`/`restore`. The file declares this itself (`aegis-data:455`) — but a comment protects nothing; this row does. Moves only with a format version and a reader for both |
| the rotation diary — `.previo/`, `delegada`, `*.parcial` under `.init-state/` | state the next rotation resumes from; a rename strands a rotation in progress |
| `aegis-plataforma` / `aegis-consumo` (dashboard uids) | Grafana keys saved views and links by uid: bookmarks and the bootstrap dashboard's cross-links die |
| the `secret-*-credenciales` key `usuario` | lives inside Secrets already in the cluster (listed in 5A.3 for the code side: the code moves with the next rotation, the object with it) |

Rule for 5B: a row leaves this table only with a destroy-and-rebuild
where the old object never coexists with the new one, or with a
versioned format that reads both. Never by a rename in the code alone.
