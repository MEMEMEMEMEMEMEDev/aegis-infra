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
| `canario` | `canary` |
| `plataforma` | `platform` |
| `ruteo` | `routes` |
| `observabilidad` | `observability` |
| `reglas` | `rules` |
| `eventos` | `events` |
| `borde` in a dashboard filename | `edge` |
| `consumo` in a dashboard filename | `usage` |

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
