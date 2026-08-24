# Protocolo: API key de un proyecto contra el gateway de AI

Blast radius: quien tenga la key puede gastar la GPU dentro de los
presupuestos del proyecto, invocando SOLO las tareas que lo nombran en
el registro. No puede pedir prompts libres, no puede leer las
conversaciones de otro proyecto, no puede tocar el cluster. Es una
credencial de CONSUMO, no de control — deliberadamente aburrida.

Referencia de diseño: `docs/architecture/ai-gateway.md` §7.1.

## La clave se parte en dos, a propósito

| Mitad | Dónde vive | Por qué ahí |
|---|---|---|
| **hash** SHA-256 | `ai-system/ai-keys` (`keys.json`) | el gateway solo necesita verificar |
| **claro** | `org-<proyecto>/ai-gateway-key` | rotarla es un acto del PROYECTO, no de la plataforma |

El gateway nunca ve el claro guardado en ningún lado: lo recibe en el
header y lo compara contra el hash. Perder el Secret del proyecto
significa emitir una key nueva, no recuperar la vieja.

## 1. Emitir (tmpfs, el claro no toca disco no cifrado)

    D=$(mktemp -d /dev/shm/aegis-ai.XXXXXX) && chmod 700 "$D"

    # El prefijo `aegisk_<proyecto>_` es DELIBERADO: hace que una key
    # filtrada sea greppeable por un escáner de secretos. Ocultar el
    # formato no protege nada —quien la tiene ya la tiene— y sí impide
    # detectar la filtración.
    KEY="aegisk_<proyecto>_$(head -c 24 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')"
    printf '%s' "$KEY" > "$D/clave"
    HASH=$(printf '%s' "$KEY" | sha256sum | cut -d' ' -f1)

## 2. Escribir las dos mitades

`kid` identifica QUÉ key se usó: aparece en cada línea de log y es lo
que permite rotar sin adivinar quién sigue usando la vieja.

    printf '{"claves":[{"tenant":"org-<proyecto>","kid":"<proy>-1","sha256":"%s"}]}\n' \
      "$HASH" > "$D/keys.json"

    # --from-file y no --from-literal: byte-preserving. Un stringData
    # armado a mano agrega un byte por el folding YAML.
    kubectl create secret generic ai-keys -n ai-system \
      --from-file=keys.json="$D/keys.json" --dry-run=client -o yaml > "$D/s1.yaml"
    kubectl create secret generic ai-gateway-key -n org-<proyecto> \
      --from-file=clave="$D/clave" --dry-run=client -o yaml > "$D/s2.yaml"

    # mv al path del repo PRIMERO, sops DESPUÉS: la creation_rule
    # matchea por path_regex y /dev/shm no matchea.
    mv "$D/s1.yaml" k8s/base/ai-system/secret-ai-keys.enc.yaml
    mv "$D/s2.yaml" k8s/organizations/org-<proyecto>/secret-ai-gateway-key.enc.yaml
    sops -e --in-place k8s/base/ai-system/secret-ai-keys.enc.yaml
    sops -e --in-place k8s/organizations/org-<proyecto>/secret-ai-gateway-key.enc.yaml

    find "$D" -type f -exec shred -u {} \; && rmdir "$D"

Agregar los dos archivos a los `secret-generator.yaml` correspondientes
(lista explícita, A7: nada de globs).

## 3. Validar el roundtrip MIRANDO EL CÓDIGO DE SALIDA

    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/aegis.key"
    sops -d <archivo> > /dev/null && echo OK || echo FALLA

**No** validar con `sops -d ... | head -c 1`. Cuando sops falla escribe
`Failed to get the data key...` por stderr, `head -c 1` imprime la `F`
y el `&&` da verde: el chequeo confirma exactamente lo contrario de lo
que pasó. Mordió el 2026-08-02 y es la misma clase que ya conocemos
—*el chequeo atado a la letra en vez de al invariante*—, acá disfrazada
de "pero si lo probé".

Ojo con el path: la identidad de esta instancia es `aegis.key`, no el
`keys.txt` que sops busca por defecto. Sin `SOPS_AGE_KEY_FILE`, sops
falla con "no such file or directory" aunque el archivo exista.

## 4. Autorizar la tarea Y la red

Una key sola no alcanza. Hacen falta las dos:

1. El proyecto tiene que estar en `tenants` de cada tarea del registro
   (`k8s/base/ai-system/registro.yaml`).
2. El namespace tiene que tener regla de NetworkPolicy hacia la puerta
   interna: una en `ai-system` (`allow-tenants-a-gateway`) y otra de
   egress en el propio tenant. Cada permiso nace con su consumidor.

Si falta (1) el gateway responde 403 y se ve. Si falta (2) la conexión
muere por timeout y el síntoma es más feo — por eso van juntas.

## 5. Rotar (sin ventana de caída)

El verificador acepta **varias keys a la vez**: esa es toda la
maquinaria de rotación.

1. Emitir la nueva con `kid` distinto (`<proy>-2`) y agregarla al array
   `claves` **sin sacar la vieja**.
2. Actualizar el Secret del proyecto con el claro nuevo; el pod toma la
   variable al reiniciar.
3. Confirmar en los logs del gateway que ya no aparece el `kid` viejo
   (`"kid":"<proy>-1"`).
4. Recién ahí sacar la entrada vieja del array.

El gateway recarga el archivo de keys en caliente cada 30 s: no hace
falta reiniciarlo en ningún paso. Y si el archivo nuevo está mal
escrito, mantiene el anterior y lo grita en el log — una rotación con
un typo no deja al servicio sin autenticar a nadie.

## 6. Revocar de urgencia

Sacar la entrada del array y sincronizar. Efecto en ≤30 s, sin
reinicios. Si hay que cortar TODO el consumo ya mismo, el corte real es
`ai cerrar`: sin engine no hay nada que gastar.
