# Checklist de rotación — LA MISMA FUENTE que la ceremonia del init

Salda C6. Principio (27 §2.3): el init greenfield EJECUTA esta
lista entera por construcción (todo material nace nuevo); una
rotación puntual ejecuta UN ítem. Un solo documento, dos usos.

## ESTO YA NO SE EJECUTA A MANO (2026-08-12)

```
init/aegis-rotate.sh          # el menú: elegís una o todas
```

Hasta hoy este documento **era** el procedimiento: once ítems que una
persona ejecutaba de memoria. Ahora es el *porqué*, y el *qué* lo hace
la herramienta. La diferencia que importa no es la comodidad:

> El último paso de cada ítem —comprobar que el consumidor real volvió a
> funcionar— no lo hacía nadie. Se rotaba, se veía que no explotaba nada
> en los primeros treinta segundos, y se daba por buena. Eso es
> exactamente la señal que no distingue "pasó" de "no se evaluó", y la
> rotación la tenía en el centro.

`aegis-rotate.sh` ahora hace el ciclo entero: inventario con la EDAD y el
RADIO de cada credencial, confirmación, invalidación del store
(archivando el `.enc` anterior en `.previo/`, no borrándolo), corrida de
la fase que regenera y sincroniza el tercero, y **verificación que puede
fallar** — un ping de webhook que tiene que dar 200 *y* una firma
inventada que tiene que dar 400; un `ssh -T` con la clave del Secret
vivo; un login real en Jenkins; los hostnames comparados contra el
snapshot previo.

Tres cosas que conviene saber antes de correrlo:

- **Preflight de red.** Si GitHub, Cloudflare, el cluster o la age key no
  responden, la rotación **no arranca**. Sobre esta máquina —WiFi, MTU
  #69, tormentas de k3s #73— arrancar con la red caída era el camino más
  corto a dejar credenciales a medio sincronizar.
- **Los reintentos son sólo de transporte.** Un timeout se reintenta; un
  «Permission denied» no. El remoto contestó, y contestó que no:
  reintentar eso es hacer tres veces lo incorrecto.
- **Si la verificación falla no se revierte solo.** Para entonces el
  tercero ya tiene la credencial nueva, y restaurar sólo el store
  recrearía la desincronización. La herramienta dice en cuál de los
  cuatro lugares —git, cluster, tercero, store— quedó cada mitad, y con
  qué comando se cierra.

El contrato viejo sigue andando (`aegis-rotate.sh [--yes] <name>...`), y
`--continuar` retoma una tanda interrumpida.

**Lo que la herramienta se niega a hacer**, y por qué está bien:

| | motivo |
|---|---|
| `cosign_*` | invalida toda firma emitida; hay que re-firmar lo desplegado ANTES de que la pub nueva entre al ClusterPolicy → ítem 2 |
| age key | es la raíz → `rotate-age-key.md`, escrito el 2026-08-12 (hasta ese día era una referencia colgada: el procedimiento del único irreducible no existía) |
| `registry_pass` | vive en diez lugares; lo rota `aegis registry`, que descubre los destinos y se planta si no coinciden → ítem 4 |
| `dk_app_rw` | rotarla RE-CREA la deploy key de escritura que #49 retiró; hay que arreglar la fase 15 primero (#83) |
| commit y push | los da una persona, igual que en `aegis-registry` |

Y un check nuevo, el **89** de `verify-static`, impide que la tabla
envejezca: toda credencial que el init genera tiene que tener receta. Una
que falte es FAIL, no un detalle.

---

Ítems (orden = sensibilidad). Siguen acá porque explican el PORQUÉ de
cada receta, y porque los que la herramienta no cubre se hacen leyendo
esto:

1. **age key** — ceremonia fase 10 (3 resguardos + roundtrip).
   Rotar además exige: recipient en .sops.yaml + `sops updatekeys`
   sobre TODOS los cifrados + recrear Secret argocd-sops-age
   (kubectl) + restart repo-server.
2. **cosign keypair** — protocolo issue-cosign-keypair §5
   (¡2 pasos! incluye RE-FIRMAR lo desplegado).
3. **write key hello-aegis-repo** — ssh-keygen → GitHub deploy key
   WRITE (retirar la vieja) → re-cifrar Secret repository →
   verificar clone de ArgoCD Y push del Image Updater (2
   consumidores).
4. **htpasswd + 4 regcreds** — protocolo registry-credentials
   (atómico o nada) + restart del pod registry.
5. **GitHub App private key** — protocolo issue-github-app §5
   (PKCS#8 + delete pod jenkins-0 + retirar key vieja).
6. **HMAC webhook Jenkins** — cuatro pasos, y el cuarto es el que se
   olvida:

   ```
   aegis secret --rotar k8s/base/platform/jenkins-secrets/secret-github-webhook-hmac.enc.yaml
   git add ... && git commit && git push
   bin/aegis-sync jenkins-secrets
   bin/aegis-webhook --aplicar
   ```

   Sin restart: `secretText` se re-lee solo.

   `aegis-secret --rotar` reemplaza al `openssl rand` a mano que decía
   acá antes. La diferencia que importa no es la comodidad: ese Secret
   lleva la etiqueta `jenkins.io/credentials-type: secretText`, que es
   lo que hace que Jenkins lo TOME como credencial, y la herramienta
   PRESERVA la metadata del documento al rotar. A mano, o con la
   herramienta antes de #53, el material nuevo quedaba bien cifrado y
   la credencial invisible, sin un solo error.

   `aegis-webhook --aplicar` reemplaza al "pegar en la App (UI)": el
   comando deriva los repos de los jobs de Jenkins, lee el HMAC del
   Secret VIVO —el que Jenkins valida de verdad— y lo reescribe en
   todos. Reescribir siempre es deliberado: GitHub nunca devuelve
   `config.secret`, así que "el hook ya existe" NO implica "está
   sincronizado", y un hook firmando con el HMAC viejo da un 400
   permanente que no dice por qué.

   **Y EL STORE DEL INIT**, que es el paso que falta en casi todas las
   rotaciones. `init/.state-secrets/hmac_jenkins.enc` guarda el material
   para que re-correr el init sea aburrido; si queda con el valor VIEJO,
   una corrida futura lo RESTAURA y deshace la rotación en silencio. Dos
   salidas:

   - `init/aegis-rotate.sh --yes hmac_jenkins` lo invalida, y la próxima
     corrida del init genera uno NUEVO — o sea que hay que volver a
     hacer el paso de `aegis-webhook`.
   - re-sembrarlo con el valor ya rotado deja los cuatro lugares (git,
     cluster, GitHub, store) con el MISMO material, y re-correr el init
     no cambia nada. Es lo que se hizo el 2026-08-07 y es lo preferible.

   Verificación, y que sea una que pueda fallar: `gh api -X POST
   repos/<owner>/<repo>/hooks/<id>/pings` y leer la entrega. Tiene que
   dar **200**. Comprobá además que una firma inventada dé **400** — si
   no, el 200 no está diciendo nada.
7. **HMAC webhook ArgoCD** — openssl rand → tokens.enc.yaml (lado
   tofu apply de github-repos) + re-cifrar Secret github-webhook +
   restart argocd-server + verificar webhook 200.
8. **TUNNEL_TOKEN** — rotar vía API/recrear tunnel → re-cifrar
   Secret → rollout cloudflared.
9. **Tokens CF (x2) y PAT** — re-emitir en la UI (protocolos
   issue-*) → tokens.enc.yaml / Secret KSOPS → REVOCAR los viejos.
10. **deploy keys read (ops-stack, hello-aegis RO)** — ssh-keygen →
    GitHub → re-cifrar → retirar viejas.
10b. **deploy keys de las ORGANIZACIONES** (`secret-<app>-repo`, una
    por repo declarado en un contrato). Faltaban en esta lista hasta
    2026-08-05: se habían creado a mano, no las producía nadie y nadie
    las rotaba (#48, #49). Ya son un comando:

    ```
    aegis secret --rotar k8s/base/platform/argocd-secrets/secret-<app>-repo.enc.yaml
    ```

    Imprime la pública para registrarla. **SIN "Allow write access"**:
    ArgoCD solo LEE, y una deploy key con escritura deja que quien
    tenga el cluster escriba en el repo de la app — la dirección
    equivocada. Las dos que existían eran read-write por el Image
    Updater, retirado en #37.

    **EL ORDEN NO ES OPCIONAL**, y es el que se siguió el 2026-08-05:

    1. rotar (el archivo cifrado ya queda con la clave nueva)
    2. registrar la pública en GitHub como **read-only**
    3. commit + push + `bin/aegis-sync argocd-secrets`
    4. esperar a que el Secret del cluster tenga la clave nueva
    5. **probar que autentica** — no alcanza con que la App esté
       Synced, porque mientras la vieja siga registrada cualquiera de
       las dos sirve:
       ```
       kubectl get secret <app>-repo -n argocd -o jsonpath='{.data.sshPrivateKey}' \
         | base64 -d > /dev/shm/k && chmod 600 /dev/shm/k
       ssh -i /dev/shm/k -o IdentitiesOnly=yes -T git@github.com   # "Hi ORG/REPO!"
       shred -u /dev/shm/k
       ```
    6. recién ahí `gh repo deploy-key delete <id> -R <owner>/<repo>`
    7. refresh duro de la App y comprobar Synced + Healthy

    Al revés —borrar antes de comprobar— deja a ArgoCD sin poder leer
    el repo.
11. **jenkins-admin** — random nuevo → re-cifrar → verificar si el
    chart re-lee existingSecret o exige restart (NO VERIFICADO —
    marcar el resultado acá la primera vez que se haga).

**Pasos que el init NO cubre y la rotación SÍ** (27 §2.3): retirar
credenciales VIEJAS del lado de los terceros (deploy keys/App keys
en GitHub, tokens en CF) y el re-firmado de imágenes (ítem 2). Un
init que corrió no deja residuos NUEVOS, pero rotar sobre un
entorno vivo deja residuos VIEJOS activos si esta parte se saltea.

Trigger de la rotación en lote: primer cliente con SLA / exposición
pública / corte a Hetzner. Revisar 1 semana antes.
