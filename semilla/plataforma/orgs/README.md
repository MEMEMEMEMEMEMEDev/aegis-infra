# orgs/ — los contratos de las organizaciones

Vacío al arrancar, y así tiene que estar: una instancia recién nacida no
tiene ninguna organización. Cada archivo `.yaml` de este directorio es
**un contrato**, y de él sale todo lo demás.

Dar de alta una organización son tres comandos:

```bash
$EDITOR orgs/mi-org.yaml            # el contrato
bin/aegis-org plan orgs/mi-org.yaml # qué cambiaría, sin escribir nada
bin/aegis-org aplicar orgs/mi-org.yaml
aegis secret create orgs/mi-org.yaml   # los que falten (nunca rota los que ya están)
bin/aegis-sync root                 # root NO tiene automated (ADR-0012)
```

El contrato más chico que hace algo:

```yaml
version: 1
organizacion: mi-org
dominio: mi-org.example.com
cuota: pequena
repo: git@github.com:mi-org/mi-app.git
servicios:
  - nombre: web
    tipo: estatico
    publico: /
```

De ahí el generador deriva el namespace, la cuota, las NetworkPolicies,
el AppProject, la Application, el ruteo y qué secretos hacen falta. Lo
que **no** sale del contrato son los números: los topes de cuota viven en
`planes.yaml`, los de AI en `planes.yaml` + `ai/tareas.yaml`, y la imagen
de cada tipo de servicio en `servicios.yaml`. Están afuera a propósito —
así se reajustan para todas las organizaciones a la vez sin editar
treinta contratos.

El contrato completo, campo por campo, con lo que cada tipo de servicio
puede y no puede declarar: **`docs/protocols/organizacion.md`**.

Dos cosas que conviene saber antes de la primera vez:

- **`publico` es una RUTA, no un booleano** (`/`, `/api`), porque lo que
  se publica es un prefijo del dominio de la organización.
- **El ruteo no se escribe**: lo deriva la plataforma del contrato. Una
  organización no puede crear sus propias `IngressRoute` — si pudiera,
  podría reclamar el hostname de otra, y eso se midió pasando (#54).
