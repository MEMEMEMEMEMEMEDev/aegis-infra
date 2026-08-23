# Rotar la age key — la raíz de confianza

**Escrito el 2026-08-12.** Cuatro lugares del stack lo citaban —dos de
ellos por sección concreta (`§A`, `§A.8/A.9`)— y el archivo no existía.
El procedimiento de rotación del único irreducible del sistema era una
referencia colgada.

| lo citaba | desde |
|---|---|
| `docs/protocols/rotation-checklist.md` | ítem 1 y la tabla de negativas |
| `init/phases/10-age-ceremony.sh:3` | «generaliza rotate-age-key.md §A» |
| `init/lib/secrets.sh:21` | «patrón rotate-age-key.md §A» |
| `init/lib/secrets.sh:406` | «rotate-age-key.md §A.8/A.9» |

---

## Por qué esta rotación es distinta a todas las demás

Todo el modelo de secretos de aegis se apoya en una frase:

> La age key descifra todo, así que es lo único que el operador
> resguarda. El resto es recuperable.

Eso convierte a esta rotación en la única que **no se puede recuperar
desde el propio sistema**. Si `sops updatekeys` queda a medias, hay
material que ya no descifra con la clave vieja (porque se le quitó) ni
con la nueva (porque no se le llegó a agregar). No hay backup que
ayude: el backup también está cifrado con la clave que se rompió.

De ahí la forma del protocolo: **se agrega la clave nueva antes de
quitar la vieja**, y entre esos dos momentos hay una verificación que
puede fallar. Durante toda la fase A los dos juegos de claves sirven, así
que no existe un instante en el que un fallo deje material ilegible.

---

## Alcance medido (2026-08-12)

```
platform/**/*.enc.yaml, *.enc.json ..... 39 archivos
init/.state-secrets/*.enc ............... 18 archivos
                                          ──
                                          57 re-cifrados
```

Más tres lugares que apuntan a la clave y hay que mover con ella:

| dónde | qué es |
|---|---|
| `platform/.sops.yaml` | **tres** `creation_rules`, cada una con su `age:` |
| `init/.age-public` | de acá sale `$AGE_PUBLIC` para todo el init |
| `argocd/argocd-sops-age` (Secret, clave `keys.txt`) | lo que usa KSOPS en el cluster para descifrar |

`init/.state-secrets/.sops.yaml` **no se edita a mano**: `persist_secret`
lo reescribe en cada llamada a partir de `$AGE_PUBLIC`. Se mueve solo
cuando se mueve `init/.age-public`.

---

## Antes de empezar

```bash
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/aegis.key
export AEGIS_RESPALDOS=/mnt/e/aegis-respaldos   # montado (#85)
init/aegis-backup.sh          # ROUNDTRIP verificado, no «tenemos backups»
```

El bundle queda cifrado con la clave **vieja**. Es deliberado: mientras
la vieja siga siendo válida —toda la fase A— ese backup es utilizable. Al
terminar la fase C hay que **volver a respaldar**, porque el bundle viejo
deja de abrirse.

Y una condición que no es negociable: la copia resguardada de la clave
vieja tiene que estar a mano y **probada**, no supuesta. Si no podés
descifrar algo con ella ahora mismo, no empieces.

---

## Fase A — la clave nueva entra, la vieja se queda

**A.1** Generar la clave nueva en tmpfs y derivar su pública.

```bash
umask 077
NUEVA=/dev/shm/age-nueva.key
age-keygen -o "$NUEVA"
PUB_NUEVA="$(age-keygen -y "$NUEVA")"
PUB_VIEJA="$(cat init/.age-public)"
echo "vieja: $PUB_VIEJA"
echo "nueva: $PUB_NUEVA"
```

Las públicas **sí** se pueden mirar e imprimir. La privada no: vive en
`/dev/shm` hasta que la resguardes.

**A.2** Resguardar la clave nueva **desde otra terminal**, nunca en este
pane. Es la regla W-01/EV-01, y viene de un incidente real: una age key
quedó en un log de tmux y esa instancia se declaró comprometida
(`HISTORIA.md:199`).

```
# en OTRA terminal:
cat /dev/shm/age-nueva.key      # guardala donde guardes tus secretos
```

**A.3** Agregar la pública nueva como **segundo** recipient, sin quitar
la vieja. Las tres reglas de `platform/.sops.yaml`:

```bash
sed -i "s|age: $PUB_VIEJA|age: $PUB_VIEJA,$PUB_NUEVA|g" platform/.sops.yaml

# contar ESTRUCTURALMENTE, no con grep: todas las reglas tienen que
# haber quedado con la clave nueva
python3 - <<PY
import yaml
reglas = yaml.safe_load(open("platform/.sops.yaml"))["creation_rules"]
con = [r for r in reglas if "$PUB_NUEVA" in r.get("age","")]
print(f"reglas: {len(reglas)}   con la clave nueva: {len(con)}")
assert len(con) == len(reglas), "hay reglas SIN la clave nueva"
PY
```

Que estén **todas** no es cosmético: si una regla queda sin la clave
nueva, los archivos que matchea sólo ese `path_regex` se quedan atrás y
el fallo aparece recién cuando alguien los toque.

Y el conteo va por YAML a propósito. `grep -c "$PUB_NUEVA"` sobre este
archivo devuelve **4** y no 3, porque la cabecera del `.sops.yaml`
menciona la clave en un comentario. Es exactamente el bache que el
stack ya tiene catalogado en H4 / check 41 —«un guard sobre YAML se
hace estructural, nunca con `grep` sobre un nombre, porque matchea
comentarios»— y esta guía cayó en él en su primera escritura.

**A.4** Re-cifrar los 39 del repo.

```bash
cd platform
find . \( -name '*.enc.yaml' -o -name '*.enc.json' \) -print0 \
  | xargs -0 -n1 sops updatekeys --yes
```

`updatekeys` **no descifra el contenido**: reescribe sólo la lista de
recipients de la cabecera. Por eso puede correr sobre los 39 sin
exponer nada.

**A.5** Re-cifrar los 18 del store. El store usa su propio config, así
que primero se le pone el recipient doble:

```bash
printf 'creation_rules:\n  - age: %s,%s\n' "$PUB_VIEJA" "$PUB_NUEVA" \
  > init/.state-secrets/.sops.yaml
for f in init/.state-secrets/*.enc; do
  sops updatekeys --yes "$f"
done
```

**A.6 — LA VERIFICACIÓN QUE PUEDE FALLAR.** Los dos juegos tienen que
abrir los 57. Con `--yes` en el paso anterior es fácil que algo haya
fallado sin que nadie mire.

```bash
for K in "$HOME/.config/sops/age/aegis.key" /dev/shm/age-nueva.key; do
  echo "── con $(basename $K) ──"; malos=0
  for f in $(find platform -name '*.enc.yaml' -o -name '*.enc.json') \
           init/.state-secrets/*.enc; do
    SOPS_AGE_KEY_FILE="$K" sops -d "$f" >/dev/null 2>&1 || { echo "  NO ABRE: $f"; malos=$((malos+1)); }
  done
  echo "  ilegibles: $malos"
done
```

**Las dos pasadas tienen que dar 0.** Si alguna no da 0, **parar acá**:
todavía no se quitó nada, así que el estado sigue siendo recuperable.
Arreglar y repetir A.4/A.5.

**A.7** Commit. En este punto el repo está en un estado seguro y vale la
pena dejarlo grabado aunque después haya que seguir.

```bash
cd platform && git add -A && git commit -m "chore(age): recipient doble — fase A de la rotación" && git push
```

---

## Fase B — el cluster y el operador pasan a la clave nueva

**B.1** El Secret que usa KSOPS:

```bash
kubectl -n argocd create secret generic argocd-sops-age \
  --from-file=keys.txt=/dev/shm/age-nueva.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd rollout restart deploy/argocd-repo-server
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=180s
```

**B.2** La clave del operador. La vieja **no se borra todavía**: se
guarda al lado, porque la fase C aún necesita comprobar que deja de
servir.

```bash
cp -a ~/.config/sops/age/aegis.key ~/.config/sops/age/aegis.key.vieja
install -m 600 /dev/shm/age-nueva.key ~/.config/sops/age/aegis.key
echo -n "$PUB_NUEVA" > init/.age-public
```

**B.3** Verificar que el cluster sigue vivo — con una señal que pueda
fallar. Un repo-server que no descifra deja las Apps sin reconciliar,
y eso no siempre se ve rápido:

```bash
platform/bin/aegis-sync --fuera-de-linea
kubectl get applications -n argocd -o custom-columns=\
'N:.metadata.name,S:.status.sync.status,H:.status.health.status' | grep -v Synced
```

Ninguna App debería quedar `Unknown` ni `Degraded`. Un `ComparisonError`
en el repo-server es la firma de «no puede descifrar».

---

## Fase C — la clave vieja deja de servir

Esta es la fase que convierte «agregué una clave» en «roté la clave».
Sin ella el sistema queda con dos raíces de confianza válidas, que es
peor que antes: la vieja —la que se quiso retirar— sigue abriendo todo.

**C.1** Sacar la pública vieja de los cuatro sitios:

```bash
sed -i "s|age: $PUB_VIEJA,$PUB_NUEVA|age: $PUB_NUEVA|g" platform/.sops.yaml

python3 - <<PY
import yaml
reglas = yaml.safe_load(open("platform/.sops.yaml"))["creation_rules"]
quedan = [r for r in reglas if "$PUB_VIEJA" in r.get("age","")]
print(f"reglas que TODAVÍA llevan la vieja: {len(quedan)}")
assert not quedan, "queda al menos una regla con la clave vieja"
PY

printf 'creation_rules:\n  - age: %s\n' "$PUB_NUEVA" > init/.state-secrets/.sops.yaml
```

El comentario de cabecera de `.sops.yaml` sigue nombrando a la clave
vieja: es documentación de la fase 10, no un recipient. Por eso el
chequeo va por YAML y no por `grep` (ver A.3).

**C.2** Re-cifrar los 57 otra vez (mismos comandos de A.4 y A.5).

**C.3 — EL DIENTE NEGATIVO.** Con la clave nueva todo abre; con la vieja
**nada** tiene que abrir. La segunda mitad es la que importa: sin ella,
«roté» y «agregué una clave y me olvidé de quitar la otra» dan
exactamente la misma señal verde.

```bash
echo "── con la NUEVA (esperado: 0 ilegibles) ──"; malos=0
for f in $(find platform -name '*.enc.yaml' -o -name '*.enc.json') init/.state-secrets/*.enc; do
  sops -d "$f" >/dev/null 2>&1 || { echo "  NO ABRE: $f"; malos=$((malos+1)); }
done; echo "  ilegibles: $malos"

echo "── con la VIEJA (esperado: TODOS ilegibles) ──"; abren=0
for f in $(find platform -name '*.enc.yaml' -o -name '*.enc.json') init/.state-secrets/*.enc; do
  SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key.vieja sops -d "$f" >/dev/null 2>&1 \
    && { echo "  TODAVÍA ABRE: $f"; abren=$((abren+1)); }
done; echo "  siguen abriendo: $abren"
```

Lo correcto es **0 ilegibles con la nueva** y **0 que sigan abriendo con
la vieja**. Cualquier archivo en la segunda lista es un archivo que la
rotación no alcanzó.

**C.4** Respaldar de nuevo. El bundle de «antes de empezar» ya no se
abre con la clave que ahora tenés.

```bash
init/aegis-backup.sh
```

**C.5 — RETIRAR LA CLAVE VIEJA. Y retirar NO es destruir.**

La primera versión de este documento decía `shred -u` acá, sin más. Está
mal, y el error es de los que sólo se descubren cuando ya es tarde: los
respaldos se cifran con `age -r $AGE_PUBLIC`, así que **destruir la
clave vieja vuelve irrecuperable todo bundle hecho antes de la
rotación**. Al 2026-08-12 son 14 bundles (7 en `legado/`, 5 en
`plataforma/`, 2 en `org-ejemplo/`), más los `.enc` archivados en
`init/.state-secrets/.previo/`.

Hay dos caminos y el primero es el bueno.

**C.5a — re-cifrar lo alcanzable (preferido).** Son 152K: tarda
segundos. Y es lo único que permite destruir la vieja *limpiamente*, sin
dejar por ahí una clave capaz de abrir material del sistema.

```bash
VIEJA=~/.config/sops/age/aegis.key.vieja
for b in "$AEGIS_RESPALDOS"/*/*.age; do
  age -d -i "$VIEJA" "$b" | age -r "$PUB_NUEVA" -o "$b.nuevo" || { echo "FALLÓ: $b"; continue; }
  # roundtrip ANTES del mv: no se declara re-cifrado sin volver a abrirlo
  if age -d -i ~/.config/sops/age/aegis.key "$b.nuevo" >/dev/null 2>&1; then
    mv "$b.nuevo" "$b"; echo "  ok  $b"
  else
    rm -f "$b.nuevo"; echo "  ROUNDTRIP FALLÓ, se deja el original: $b"
  fi
done
```

Los `.enc` de `.previo/` van con `sops updatekeys` como el resto —
están bajo el `.sops.yaml` del store, así que C.2 ya los alcanzó si el
glob los incluyó. **Verificalo**: `ls init/.state-secrets/.previo/`.

Recién con todo re-cifrado y verificado:

```bash
shred -u "$VIEJA"
shred -u /dev/shm/age-nueva.key      # ya está en ~/.config y resguardada
```

**C.5b — retirar sin destruir (cuando hay copias inalcanzables).** Si
hay bundles offsite, en frío, o en un disco que no está conectado
—cualquier copia que C.5a no pueda tocar— entonces la clave vieja **no
se destruye**. Se retira, que es otra cosa, y tiene requisitos:

- **Sale de todos los sitios operativos igual**: las tres
  `creation_rules` de `.sops.yaml`, el Secret `argocd-sops-age`,
  `~/.config/sops/age/`. Archivada **no** significa en uso: nada nuevo
  se cifra con ella y ningún proceso la tiene a mano.
- **Va al resguardo offline del operador**, con una etiqueta que diga
  qué abre, desde y hasta qué fecha, y cuándo puede morir. Una clave sin
  etiqueta, a los seis meses, es indistinguible de una clave viva — y
  nadie se anima a borrarla, así que se queda para siempre.
- **NUNCA dentro del árbol de respaldos que descifra.** Es circular:
  quien consiga ese disco tendría el candado y la llave juntos, y el
  cifrado deja de proteger absolutamente nada. Va donde vive el
  resguardo de la clave *actual*, que es otro lugar por definición.

La regla de fondo, y aplica a cualquier clave del sistema, no sólo a
esta: **invalidar para todo uso nuevo es obligatorio; destruir es una
decisión aparte, y sólo se puede tomar cuando ya nada cifrado con ella
importa.**

**C.6** Commit y push.

---

## Si algo sale mal

| dónde | qué pasa | qué hacer |
|---|---|---|
| fase A | nada es irreversible: la clave vieja sigue siendo recipient de todo | arreglar y repetir A.4/A.5 |
| fase B | el cluster no descifra, pero el repo está bien | volver el Secret `argocd-sops-age` a la clave vieja y reiniciar repo-server |
| fase C, antes de C.5 | la clave vieja todavía existe | volver a poner los dos recipients y re-correr updatekeys |
| fase C, tras C.5a | **la clave vieja ya no existe** | sólo sirve el resguardo de la nueva; por eso A.2 va antes que todo |
| fase C, tras C.5b | la vieja existe pero está archivada offline | recuperarla del resguardo abre los bundles antiguos; nada más |

El orden de este documento no es estético. Cada paso está donde está
para que el anterior siga siendo reversible.

---

## Lo que este protocolo NO cubre

- **Los `.enc` que no estén en los dos árboles medidos.** Si aparece un
  cuarto sitio con material cifrado, este protocolo lo deja atrás en
  silencio. El conteo de 39 + 18 es de 2026-08-12: **verificalo antes de
  empezar**, no lo copies.
- **Copias de respaldo que no estén montadas o accesibles** en el
  momento de C.5a. El bucle sólo alcanza lo que ve. Si tenés bundles
  offsite, entrás por C.5b, y eso es una decisión que se escribe — no
  un descuido que se descubre el día que hace falta restaurar.
- **Ejercitarlo.** Al 2026-08-12 este documento está escrito y sus
  comandos verificados uno por uno contra la instancia viva, pero la
  rotación completa **todavía no se corrió de punta a punta**. Hasta que
  se corra, esto es un plan, no un procedimiento probado. Anotá acá la
  fecha la primera vez que se ejecute.
