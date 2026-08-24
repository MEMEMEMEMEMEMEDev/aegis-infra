# Plantilla `base` — un servicio HTTP pelado

La mínima que compila y despliega (caminos/design.md §4). Existe para
que `aegis-app nueva <org> --plantilla base` te deje, en una corrida y
sin tocar el mundo, todo lo que el camino artesano escribe a mano.

## Qué levanta

| pieza | de dónde sale |
|---|---|
| `orgs/<org>.yaml` | `contrato.yaml.tpl`, con `__ORG__`/`__DOMINIO__`/`__REPO__` resueltos |
| `.aegis-app/<org>/app/` | `repos/app/` — el esqueleto del repo de la app |
| manifiestos de `k8s/organizations/org-<org>/` + jobs + borde | NO son de esta plantilla: los deriva `bin/aegis-org` DEL CONTRATO |
| secretos `.enc.yaml` | tampoco: los crea `aegis secret create` |

El esqueleto es Go con **cero dependencias externas** a propósito
(caminos §5, presupuesto de podredumbre): un árbol de dependencias
vacío no puede pudrirse. Trae `main.go` + `go.mod`, `Containerfile`
no-root (PSS restricted), `k8s/base/` + `k8s/overlays/dev/` con el
digest-marcador que el pipeline reescribe, y `ci/escribir-digest.mjs`
(copiado del canónico en `docs/protocols/templates/`). El `Jenkinsfile`
**no** vive acá: lo instancia `aegis-org` desde el template canónico al
mismo staging (caminos §2b) — un solo template, cero CHANGEME copiados.

## Que se evapora tras instanciar

La plantilla genera el contrato y el código inicial y **desaparece de
tu vida** (caminos §0.3): nada de lo generado recuerda de dónde vino ni
vuelve a leerla. No hay "upgrade de plantilla", no sos "una app base":
sos un artesano con un contrato y un repo, igual que quien los escribió
a mano. Editar esta carpeta no cambia ninguna organización ya creada.

## Cómo se personaliza después (el camino artesano)

Editando **el contrato**, que es la única verdad, y reaplicando:

    $EDITOR orgs/<org>.yaml          # sumar postgres, bucket, ai, otro servicio…
    bin/aegis-org aplicar orgs/<org>.yaml
    aegis secret create orgs/<org>.yaml   # si aparecieron secretos nuevos

(`bin/aegis-app nueva <org>` sin `--plantilla` corre exactamente esos
dos pasos por vos.) El código de la app se personaliza en SU repo, como
cualquier repo: la referencia viva de un camino más completo —dos
imágenes, base, bucket, AI— es `ejemplo-app` (orgs/ejemplo.yaml).
