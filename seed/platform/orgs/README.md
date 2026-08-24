# orgs/ — the organizations' contracts

Empty at the start, and that is how it has to be: a newborn instance has
no organizations. Every `.yaml` file in this directory is **one
contract**, and everything else is derived from it.

Onboarding an organization is a handful of commands:

```bash
$EDITOR orgs/my-org.yaml              # the contract
aegis org plan  orgs/my-org.yaml      # what would change, writing nothing
aegis org apply orgs/my-org.yaml
aegis secret create orgs/my-org.yaml  # the ones that are missing (never rotates the ones already there)
aegis sync root                       # root has no automated syncPolicy (ADR-0012)
```

The smallest contract that does anything:

```yaml
version: 1
organizacion: my-org
dominio: my-org.example.com
cuota: pequena
repo: git@github.com:my-org/my-app.git
servicios:
  - nombre: web
    tipo: estatico
    publico: /
```

From that, the generator derives the namespace, the quota, the
NetworkPolicies, the AppProject, the Application, the routing and which
secrets are needed. What does **not** come out of the contract are the
numbers: the quota ceilings live in `plans.yaml`, the AI ones in
`plans.yaml` + `ai/tasks.yaml`, and the image for each service type in
`services.yaml`. They are outside on purpose — that way they can be
readjusted for every organization at once without editing thirty
contracts.

The full contract, field by field, with what each service type may and
may not declare: **`docs/protocols/organization.md`**.

> The contract's field names are still in Spanish (`organizacion`,
> `cuota`, `servicios`, `nombre`, `tipo`, `publico`). They are the last
> piece of the move to English, and they move as one coordinated change
> together with the generator, this document and the example contracts —
> because a contract whose keys half-changed is a contract that silently
> stops being read.

Two things worth knowing before the first time:

- **`publico` is a PATH, not a boolean** (`/`, `/api`), because what is
  published is a prefix of the organization's domain.
- **The routing is not written by hand**: the platform derives it from
  the contract. An organization cannot create its own `IngressRoute` —
  if it could, it could claim another organization's hostname, and that
  was measured happening (#54).
