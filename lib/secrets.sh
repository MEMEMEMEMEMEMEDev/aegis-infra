#!/usr/bin/env bash
# aegis-init lib/secrets.sh — EL MECANISMO DE SECRETOS. INERTE por
# diseño: define CÓMO se genera/cifra/resguarda cuando el init corra;
# este artefacto no genera material real.
#
# Principios horneados (cada uno nació de un bache real; refs = doc 26):
#  - random + resguardo cifrado en el store (D11) como camino
#    PRINCIPAL — el operador solo resguarda LA AGE KEY; entrada
#    manual = excepción explícita (veredicto 20.2).
#  - el agente/init maneja MECÁNICA sin ver valores: nada de secretos
#    en argv (/proc/PID/cmdline — A27), nada en logs, shape-checks
#    solo de LONGITUD.
#  - byte-preserving SIEMPRE: kubectl --from-file, jamás stringData a
#    mano (A6: 1 byte de folding rompió un HMAC real).
#  - SOPS: mv al repo PRIMERO, cifrar DESPUÉS (A5: path_regex) +
#    roundtrip de validación SIEMPRE.
#  - credenciales compartidas: UN origen, derivación en el MISMO
#    proceso, commit atómico (A27: mismatch real de 6 días).
#  - irreemplazables (age, cosign, write key): ceremonia con
#    validación de resguardo por ROUNDTRIP REAL, no confirmación
#    verbal (veredicto 20.3; patrón rotate-age-key.md §A).
#  - material transitorio SOLO en tmpfs (/dev/shm) con shred al salir.

set -euo pipefail

# ── área de trabajo efímera ─────────────────────────────────────────
# secrets_workdir: tmpfs por-fase, chmod 700, destruida con shred en
# el EXIT trap. TODO material en claro vive SOLO acá y SOLO durante
# la fase.
secrets_workdir() {
    umask 077   # W-03: todo archivo que cree la fase nace 600/700
                # (store, tmpfs, .enc) — cierra "material nace 0664"
    SECRETS_TMP="$(mktemp -d /dev/shm/aegis-init.XXXXXX)"
    chmod 700 "$SECRETS_TMP"
    # limpiar SIEMPRE, pase lo que pase; pasos separados, sin && (regla)
    # W-03: INT/TERM además de EXIT — Ctrl-C dispara el shred de tmpfs
    # (antes solo EXIT: un Ctrl-C dejaba material en claro en /dev/shm):
    trap 'secrets_cleanup; exit 130' INT TERM
    trap 'secrets_cleanup' EXIT
}
secrets_cleanup() {
    [[ -n "${SECRETS_TMP:-}" && -d "$SECRETS_TMP" ]] || return 0
    find "$SECRETS_TMP" -type f -exec shred -u {} \;
    # rm -rf, NO rmdir (corrida #9): registry_creds crea el subdir
    # docker/ dentro de SECRETS_TMP; shred destruye los ARCHIVOS pero
    # el subdir vacío queda → rmdir del padre falla → la fase entera
    # se marca FALLIDA con todo su trabajo hecho. El material sensible
    # ya lo destruyó shred; rm -rf solo limpia el esqueleto de dirs:
    rm -rf "$SECRETS_TMP"
}

# ── entorno SOPS re-derivable EN EL PUNTO DE USO ────────────────────
# Bug 5 validación #3: phase_env re-deriva antes de cada fase, pero
# el entorno se perdió igual en algún subshell del camino --from.
# Fix de la CLASE: toda función de esta lib que invoque sops
# re-deriva ella misma desde disco (derivar, no acarrear — el mismo
# principio, aplicado un nivel más abajo, donde ya no hay huecos).
sops_env() {
    local k="$HOME/.config/sops/age/aegis.key"
    if [[ ! -f "${SOPS_AGE_KEY_FILE:-/nonexistent}" && -f "$k" ]]; then
        export SOPS_AGE_KEY_FILE="$k"
    fi
    if [[ -z "${AGE_PUBLIC:-}" && -f "$AEGIS_HOME/.age-public" ]]; then
        AGE_PUBLIC="$(cat "$AEGIS_HOME/.age-public")"
        export AGE_PUBLIC
    fi
    return 0
}

# ── cifrado AL REPO con config EXPLÍCITO ────────────────────────────
# Patrón A validación #3: sops sin --config busca .sops.yaml en el
# CWD — y el init corre desde init/, no desde platform/ → "no
# matching creation rules" en TODO cifrado al repo. El fix del store
# (persist_secret) no se había propagado. Fix de la CLASE: único
# punto de cifrado-al-repo, con el .sops.yaml de platform/ explícito
# (path_regex resuelve relativo al config, no al CWD). verify-static
# check 16 caza cualquier sops -e futuro que se lo saltee.
sops_encrypt_repo() {   # <archivo bajo platform/>
    sops_env
    sops --config "$PLATFORM_DIR/.sops.yaml" -e --in-place "$1"
}

# ── store de persistencia CIFRADA entre corridas ────────────────────
# Bug 6 corrida #2: retomar con --from REGENERABA secretos ya
# registrados en terceros (deploy keys huérfanas, HMACs nuevos que
# no matcheaban los webhooks) → ciclo infernal de rehacer todo.
# Fix de raíz: todo secreto GENERADO se persiste cifrado con la age
# key (mismo nivel de protección que los .enc.yaml del repo) en
# .state-secrets/, y las fases RESTAURAN antes de generar.
# Modelo: la age key descifra todo → el ÚNICO irreducible que el
# operador resguarda es la age key; el resto es recuperable.
STATE_SECRETS="${AEGIS_HOME}/.state-secrets"

persist_secret() {   # persist_secret <nombre> <archivo-en-tmpfs>
    local name="$1" src="$2"
    sops_env
    : "${AGE_PUBLIC:?persist_secret necesita AGE_PUBLIC (fase 10+)}"
    mkdir -p "$STATE_SECRETS"; chmod 700 "$STATE_SECRETS"
    # config PROPIO y explícito del store: sin él, sops busca un
    # .sops.yaml por path y "no matching creation rules" dejaba un
    # .enc VACÍO por la redirección (bug cazado por el harness de
    # la sesión 6 — el fallo era silencioso):
    printf 'creation_rules:\n  - age: %s\n' "$AGE_PUBLIC" \
        > "$STATE_SECRETS/.sops.yaml"
    # P2.1 auditoría 2026-07-18: la redirección `> $name.enc` TRUNCA
    # el ciphertext previo ANTES de que sops corra — si sops falla en
    # un re-run, el .enc queda en 0 bytes y se PIERDE material ya
    # sincronizado con terceros (deploy keys, HMACs). Escritura a
    # .tmp + roundtrip sobre el .tmp + mv atómico: el .enc bueno
    # sobrevive a cualquier fallo intermedio:
    sops --config "$STATE_SECRETS/.sops.yaml" --encrypt \
        --input-type binary --output-type binary "$src" \
        > "$STATE_SECRETS/$name.enc.tmp" \
        || { rm -f "$STATE_SECRETS/$name.enc.tmp"; die "persist de $name falló (el .enc previo queda INTACTO)"; }
    # roundtrip SIEMPRE (la regla del artefacto), contra el .tmp:
    sops --decrypt --input-type binary --output-type binary \
        "$STATE_SECRETS/$name.enc.tmp" | cmp -s - "$src" \
        || { rm -f "$STATE_SECRETS/$name.enc.tmp"; die "roundtrip del store falló para $name (el .enc previo queda INTACTO)"; }
    mv "$STATE_SECRETS/$name.enc.tmp" "$STATE_SECRETS/$name.enc"
    log_info "persistido cifrado: $name (re-runs lo reutilizan)"
}

restore_secret() {   # restore_secret <nombre> [dest-en-tmpfs]
    # Códigos: 0 restaurado; 1 NO existe (el caller puede generar);
    # 2 EXISTE pero no descifra. Corrida #11: sops falló MUDO (0
    # chars, entorno de la age key) y "no descifra" se trataba igual
    # que "no existe" → el caller REGENERABA — exactamente lo que el
    # store existe para impedir (HMACs/keys ya registrados en
    # terceros; en la fase 80 invalidaría las firmas cosign). El 2
    # va con el error de sops a stderr, VISIBLE aunque el caller
    # capture stdout con $():
    local name="$1" dest="$SECRETS_TMP/${2:-$1}"
    sops_env
    [[ -f "$STATE_SECRETS/$name.enc" ]] || return 1
    if ! sops --decrypt --input-type binary --output-type binary \
            "$STATE_SECRETS/$name.enc" > "$dest" 2>"$dest.sops-err" \
       || [[ ! -s "$dest" ]]; then
        log_error "store: $name.enc EXISTE pero sops NO lo descifró — NO se regenera. ¿SOPS_AGE_KEY_FILE apunta a la key correcta? (esperada: ~/.config/sops/age/aegis.key). stderr de sops:"
        head -c 400 "$dest.sops-err" >&2 || true
        echo >&2
        rm -f "$dest" "$dest.sops-err"
        return 2
    fi
    rm -f "$dest.sops-err"
    chmod 600 "$dest"
    log_info "restaurado del store: $name (sin regenerar)"
    printf '%s' "$dest"
}

# store_rc_guard <rc> <nombre> — el guardián del código 2: los
# callers que ante "restore falló" GENERAN deben distinguir ausencia
# (rc 1, generar es correcto) de no-descifra (rc 2, generar pisa un
# secreto vivo). Un solo punto para no repetir el die en cada caller:
store_rc_guard() {
    (( ${1:-0} != 2 )) || die "store: '$2' existe cifrado pero no descifra — arreglar el entorno de la age key y re-correr la fase (regenerarlo desincronizaría terceros/firmas)"
}

# gen_or_restore <nombre> <gen_fn> [args...] — la forma canónica:
# restaura si existe; si no, genera con la fn dada Y persiste.
# Devuelve el path en tmpfs. Idempotencia de secretos estructural.
gen_or_restore() {
    local name="$1" gen_fn="$2"; shift 2
    local out rc=0
    out="$(restore_secret "$name")" || rc=$?
    store_rc_guard "$rc" "$name"        # rc 2 = no-descifra: PARAR
    if (( rc == 0 )); then
        printf '%s' "$out"; return 0
    fi
    out="$("$gen_fn" "$name" "$@")"
    persist_secret "$name" "$out"
    printf '%s' "$out"
}

# variante para keypairs SSH (dos archivos, privada + .pub):
gen_or_restore_keypair() {   # <nombre> <comment>
    local name="$1" comment="$2" priv rc=0
    priv="$(restore_secret "$name")" || rc=$?
    store_rc_guard "$rc" "$name"        # rc 2 = no-descifra: PARAR
    if (( rc == 0 )); then
        rc=0
        restore_secret "$name.pub" "$name.pub" >/dev/null || rc=$?
        store_rc_guard "$rc" "$name.pub"
        if (( rc != 0 )); then
            # P2.2 auditoría 2026-07-18: acá se REGENERABA el par
            # entero por faltar SOLO el .pub — desincronizando la
            # deploy key viva en GitHub (la privada seguía siendo
            # válida). La pública se DERIVA de la privada, que es la
            # fuente de verdad (el comment del -C original se pierde:
            # cosmético; la key registrada no cambia):
            log_warn "store sin $name.pub — DERIVO la pública de la privada existente (no se regenera el par: la deploy key registrada sigue válida)"
            ssh-keygen -y -f "$priv" > "$priv.pub" \
                || die "no pude derivar la pública de $name — ¿privada corrupta en el store?"
            persist_secret "$name.pub" "$priv.pub"
        fi
    else
        priv=""
    fi
    if [[ -z "${priv:-}" ]]; then
        priv="$(gen_ssh_keypair "$name" "$comment")"
        persist_secret "$name" "$priv"
        persist_secret "$name.pub" "$priv.pub"
    fi
    printf '%s' "$priv"
}

# ── generación (entropía correcta por tipo) ─────────────────────────
# Cada generador escribe a UN archivo en $SECRETS_TMP y devuelve el
# path. NUNCA imprime el valor. La longitud se reporta con wc -c
# (shape-check permitido: solo longitud).

gen_hex32() {           # HMACs webhook (ArgoCD, Jenkins) — 32 bytes hex
    local out="$SECRETS_TMP/$1"
    # corrida #12 (bug raíz de la 60): `openssl rand -hex 32 > out`
    # deja un \n final. El Secret K8s es byte-preserving (lo conserva)
    # pero GitHub/gh api trimean su lado → los DOS lados del HMAC
    # difieren en UN byte → firmas distintas → 400 determinista en
    # TODA delivery. tr -d '\n' = byte-idéntico en ambos lados:
    openssl rand -hex 32 | tr -d '\n' > "$out"
    log_info "generado $1 ($(wc -c < "$out") bytes)"
    printf '%s' "$out"
}

# assert_no_newline <path> [label] — corrida #12: un secreto de TEXTO
# que viaja a DOS lados (Secret K8s byte-preserving vs API externa que
# trimea) debe estar libre de \n final o los lados divergen en
# silencio. Caza también material VIEJO del store (generado con el
# gen_hex32 pre-fix y RESTAURADO byte-idéntico en re-runs):
assert_no_newline() {
    local f="$1" label="${2:-$1}"
    [[ "$(tail -c1 "$f" | od -An -tx1 | tr -d ' \n')" != "0a" ]] || \
        die "$label termina en \\n (0x0a) — HMAC asimétrico entre el Secret K8s y GitHub (corrida #12). Si viene del store viejo: borrar .state-secrets/${label}.enc y re-correr la fase para regenerar limpio (OJO: re-sincroniza el webhook vía PATCH, y el plugin de Jenkins carga el HMAC al boot — restart del statefulset si Jenkins ya corre)"
}

gen_password_b64() {    # passwords random (htpasswd, jenkins-admin)
    local out="$SECRETS_TMP/$1"
    openssl rand -base64 32 | tr -d '\n' > "$out"
    log_info "generado $1 ($(wc -c < "$out") bytes)"
    printf '%s' "$out"
}

gen_ssh_keypair() {     # deploy keys — ed25519 sin passphrase
    local name="$1" comment="$2"
    ssh-keygen -t ed25519 -N "" -C "$comment" -f "$SECRETS_TMP/$name" \
        -q
    log_info "keypair $name generado (pub: $(cut -d' ' -f1,2 \
        < "$SECRETS_TMP/$name.pub" | head -c 40)...)"
    printf '%s' "$SECRETS_TMP/$name"     # privada; pública en .pub
}

gen_age_key() {         # LA raíz de confianza
    # NO setea variables del padre (H4 validación #1: la función
    # corre en el subshell del $() y cualquier variable muere ahí).
    # La pública la deriva el CALLER del archivo, con la herramienta
    # oficial: AGE_PUBLIC="$(age-keygen -y "$path")".
    local out="$SECRETS_TMP/age.key"
    age-keygen -o "$out" 2>/dev/null
    log_info "age key generada en tmpfs"
    printf '%s' "$out"
}

gen_cosign_keypair() {  # autoridad de firma. Password: ver ceremonia.
    # Bache A43 horneado: en container, ejecutar con
    #   --user "$(id -u):$(id -g)" o el keypair queda owned por 65532.
    local passfile="$1"   # archivo con la password (de gen_password_b64
                          # o de prompt_secret_manual)
    ( cd "$SECRETS_TMP" && \
      COSIGN_PASSWORD="$(cat "$passfile")" cosign generate-key-pair )
    log_info "cosign keypair generado (cosign.key/cosign.pub en tmpfs)"
}

# materialize <filename> <valor> — escribe un valor auxiliar NO
# secreto (url, name, type, ids) a tmpfs byte-preserving (sin \n) y
# devuelve el path. Existe para que los pares key=path que consume
# make_enc_secret tengan el archivo listo ANTES de cifrar — el bug
# de orden que motivó este helper era real (fase 15, || true).
materialize() {
    local out="$SECRETS_TMP/$1"; shift
    printf '%s' "$*" > "$out"
    printf '%s' "$out"
}

# entrada manual = EXCEPCIÓN. Doble tipeo + largo mínimo. Sin eco.
# (los echo de salto de línea van a STDERR — el stdout retorna el
#  path y NADA más; H4 validación #1)
prompt_secret_manual() {
    local label="$1" minlen="${2:-16}" out="$SECRETS_TMP/$3"
    local v1 v2
    while :; do
        read -rsp "valor para ${label}: " v1 \
            || die "stdin cerrado pidiendo ${label} — en desatendido este valor entra por archivo (ver --non-interactive)"
        echo >&2
        read -rsp "repetí ${label}: " v2 \
            || die "stdin cerrado pidiendo ${label}"
        echo >&2
        [[ "$v1" == "$v2" ]] || { log_warn "no coinciden; de nuevo"; continue; }
        (( ${#v1} >= minlen )) || { log_warn "mínimo ${minlen} chars"; continue; }
        break
    done
    printf '%s' "$v1" > "$out"
    unset v1 v2
    printf '%s' "$out"
}

# ── derivaciones atómicas (mismo proceso, un origen) ────────────────
# derive_htpasswd_and_regcreds: del password del registry deriva el
# htpasswd Y los 4 dockerconfigjson EN LA MISMA LLAMADA. Es imposible
# generar "un lado" suelto — la atomicidad es estructural (27 §2a.M2).
derive_htpasswd_and_regcreds() {
    local user="$1" passfile="$2" registry_host="$3"
    # htpasswd bcrypt vía stdin (nunca argv):
    htpasswd -nBi "$user" < "$passfile" > "$SECRETS_TMP/htpasswd"
    # dockerconfigjson (jq arma el JSON; el valor nunca pasa por argv
    # de un proceso externo — jq lo lee con --rawfile):
    jq -n --rawfile pass "$passfile" \
          --arg user "$user" --arg host "$registry_host" \
          '{auths: {($host): {username: $user, password: ($pass),
            auth: (($user + ":" + $pass) | @base64)}}}' \
        > "$SECRETS_TMP/dockerconfig.json"
    log_info "htpasswd + dockerconfigjson derivados del MISMO origen"
}

# ── empaquetado a Secret K8s cifrado (KSOPS) ────────────────────────
# make_enc_secret: kubectl --from-file (data:, byte-preserving) →
# mv al PATH DEL REPO → sops -e --in-place → ROUNDTRIP de validación.
# El orden es la regla A5/A6 codificada; no hay forma de usarlo mal.
#   uso: make_enc_secret <name> <ns> <repo_dest.enc.yaml> \
#          [--type <k8s-secret-type>] [--label k=v]... \
#          [--annotation k=v]... key=path...
# --type (corrida #9): `create secret generic` produce type OPAQUE, y
# imagePullSecrets SOLO funciona con kubernetes.io/dockerconfigjson —
# el kubelet IGNORA un Opaque como pull secret ("no basic auth
# credentials") aunque el MISMO secret funcione montado como volumen.
# El type queda en claro post-SOPS (encrypted_regex = ^(data|
# stringData)$). Recordar A34: type es INMUTABLE — cambiar el type de
# un Secret ya vivo requiere kubectl delete + re-sync.
make_enc_secret() {
    local name="$1" ns="$2" dest="$3"; shift 3
    local args=() labels=() annots=()
    while (($#)); do case "$1" in
        --type)       args+=(--type="$2"); shift 2 ;;
        --label)      labels+=("$2"); shift 2 ;;
        --annotation) annots+=("$2"); shift 2 ;;
        *)            args+=(--from-file="$1"); shift ;;
    esac; done
    local tmp_yaml="$SECRETS_TMP/${name}.yaml"
    kubectl create secret generic "$name" -n "$ns" \
        --dry-run=client -o yaml "${args[@]}" > "$tmp_yaml"
    local kv
    for kv in "${labels[@]:-}"; do [[ -n "$kv" ]] && \
        kubectl label -f "$tmp_yaml" --local --dry-run=client -o yaml \
            "$kv" > "$tmp_yaml.n" && mv "$tmp_yaml.n" "$tmp_yaml"; done
    for kv in "${annots[@]:-}"; do [[ -n "$kv" ]] && \
        kubectl annotate -f "$tmp_yaml" --local --dry-run=client -o yaml \
            "$kv" > "$tmp_yaml.n" && mv "$tmp_yaml.n" "$tmp_yaml"; done
    # A5: PRIMERO al repo (path_regex de .sops.yaml), DESPUÉS cifrar
    # (vía el helper con --config explícito — patrón A validación #3):
    mv "$tmp_yaml" "$dest"
    sops_encrypt_repo "$dest"
    # roundtrip SIEMPRE — valida regla y recipient sin mostrar valores:
    sops -d "$dest" | grep -q '^kind: Secret' \
        || die "roundtrip SOPS falló para $dest"
    log_ok "Secret $ns/$name cifrado en $dest (roundtrip OK)"
}

# ── credenciales del registry para gates del init ───────────────────
# registry_creds <reg_host:puerto> <cluster_ip>: materializa en tmpfs,
# leyendo del cluster (mecánica, sin mostrar valores — regla no-print):
#   $SECRETS_TMP/registry.netrc   (curl --netrc-file; machine = host y
#                                  también la IP, para gates por --resolve
#                                  o por IP directa)
#   $SECRETS_TMP/aegis-ca.crt     (CA T1 → --cacert / --registry-cacert)
#   $SECRETS_TMP/docker/config.json (DOCKER_CONFIG para cosign; auths
#                                  keyed por host Y por IP)
registry_creds() {
    local reg_host="$1" cluster_ip="$2"
    kubectl -n jenkins-system get secret regcred-internal \
        -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d \
        > "$SECRETS_TMP/dockercfg.json"
    mkdir -p "$SECRETS_TMP/docker"
    python3 - "$SECRETS_TMP/dockercfg.json" "$reg_host" "$cluster_ip" \
        "$SECRETS_TMP/registry.netrc" "$SECRETS_TMP/docker/config.json" <<'EOF'
import base64, json, sys
src, reg_host, ip, netrc_out, cfg_out = sys.argv[1:6]
port = reg_host.rsplit(":", 1)[1]
cfg = json.load(open(src))
auth = cfg["auths"][reg_host]["auth"]
user, pw = base64.b64decode(auth).decode().split(":", 1)
with open(netrc_out, "w") as f:
    f.write(f"machine {reg_host.split(':')[0]} login {user} password {pw}\n")
    f.write(f"machine {ip} login {user} password {pw}\n")
json.dump({"auths": {reg_host: {"auth": auth},
                     f"{ip}:{port}": {"auth": auth}}}, open(cfg_out, "w"))
EOF
    chmod 600 "$SECRETS_TMP/registry.netrc" "$SECRETS_TMP/docker/config.json"
    kubectl -n cert-manager get secret aegis-internal-ca \
        -o jsonpath='{.data.ca\.crt}' | base64 -d > "$SECRETS_TMP/aegis-ca.crt"
    log_info "creds del registry materializadas en tmpfs (netrc+CA+docker cfg)"
}

# ── ceremonia de resguardo (irreemplazables) ────────────────────────
# ceremony_backup: "GUARDÁ ESTO AHORA — NO SE VUELVE A MOSTRAR".
# El valor se muestra UNA vez (es la excepción deliberada: el
# OPERADOR debe verlo para guardarlo — principio secreto-al-operador)
# y el resguardo se VALIDA por roundtrip real, no por confirmación:
#   - age key: cifrar un canary con la pública → el operador descifra
#     usando SOLO la copia resguardada (rotate-age-key.md §A.8/A.9).
#   - cosign: firmar un blob → verificar con la pub + la password
#     RE-TIPEADA desde el resguardo.
#   - write key: fingerprint mostrada; el operador la re-lee desde
#     GitHub tras registrarla y el init compara.
# gate_red SIEMPRE antes de mostrar (ROJO: exposición deliberada).
ceremony_backup() {
    local label="$1" file="$2" validate_fn="$3"
    # P0.3 auditoría 2026-07-18 — camino DESATENDIDO: no hay operador
    # que mire la pantalla. El resguardo va a AEGIS_AGE_BACKUP_FILE
    # (path que el LANZADOR eligió, idealmente tmpfs suyo); moverlo a
    # resguardo real es responsabilidad de quien lanzó la corrida. El
    # roundtrip de validación sigue siendo REAL (validate_fn lee de
    # ese archivo):
    if ni_mode; then
        : "${AEGIS_AGE_BACKUP_FILE:?--non-interactive requiere AEGIS_AGE_BACKUP_FILE (destino del resguardo de la age key, idealmente en /dev/shm del lanzador)}"
        [[ "$AEGIS_AGE_BACKUP_FILE" == /dev/shm/* ]] || \
            log_warn "AEGIS_AGE_BACKUP_FILE fuera de /dev/shm — va a tocar disco persistente; mover a resguardo y borrar con shred"
        run_cmd install -m 600 "$file" "$AEGIS_AGE_BACKUP_FILE"
        log_warn "resguardo de ${label} ESCRITO en $AEGIS_AGE_BACKUP_FILE — moverlo a tu resguardo real y destruir la copia AHORA"
        gate "resguardo-${label}" "$validate_fn"
        return 0
    fi
    # W-01 / EV-01 (2026-07-21): la clave NUNCA se imprime al pane.
    # tmux pipe-pane, script(1), asciinema y los transcripts de agentes
    # graban el pane entero, y el viejo guard [[ -t 1 ]] no detecta la
    # clase (bajo tmux stdout SIGUE siendo un TTY, y clear no borra el
    # scrollback). Modelo robusto: el valor no transita por el canal
    # compartido — se escribe a tmpfs y el operador lo lee desde OTRA
    # terminal, fuera de este pane. Es el MISMO mecanismo del camino
    # --non-interactive de arriba. El roundtrip de validación se conserva.
    local shm_out="/dev/shm/aegis-resguardo-$$"   # sin $label: EV-12
    ( umask 077; run_cmd install -m 600 "$file" "$shm_out" )
    gate_red "Resguardo de ${label}: se lee desde OTRA terminal, NO en este pane"
    human_step "Resguardo de ${label} (CÓMO, paso a paso)" \
        "1. Abrí OTRA terminal en este host (NO este pane del init)." \
        "2. Corré ahí:  cat $shm_out" \
        "3. Guardá el valor donde guardes tus secretos (gestor, papel," \
        "   pendrive — el init no asume ninguno)." \
        "4. A continuación el init te lo RE-PIDE desde tu copia para" \
        "   validar el resguardo de verdad (roundtrip)." \
        "5. El init destruye la copia de /dev/shm apenas validás."
    # validación REAL del resguardo — el operador usa SU COPIA:
    gate "resguardo-${label}" "$validate_fn"
    run_cmd rm -f "$shm_out"   # tmpfs: rm libera; shred es cosmético (M1.11)
}

# validadores de ceremonia (uno por irreemplazable):
validate_age_backup() {
    # canary cifrado con la pública; descifrar SOLO con la copia que
    # el operador dice haber resguardado. GUIADO (H5 validación #1):
    # el init PIDE la key por prompt — el operador pega una línea,
    # no edita archivos. Plan B documentado en el propio prompt.
    local canary="$SECRETS_TMP/canary.txt"
    echo "aegis-init-canary-$$" > "$canary"
    # camino desatendido (P0.3): la copia resguardada ES el archivo
    # que ceremony_backup escribió — el roundtrip la usa directo:
    if ni_mode; then
        ( cd "$SECRETS_TMP" && \
          sops --encrypt --age "$AGE_PUBLIC" "$canary" > "$canary.enc" )
        SOPS_AGE_KEY_FILE="$AEGIS_AGE_BACKUP_FILE" \
            sops -d "$canary.enc" | grep -q "aegis-init-canary-$$"
        return $?
    fi
    # cd a tmpfs para el encrypt: aun con --age explícito, sops busca
    # .sops.yaml desde el CWD hacia arriba y si encuentra uno cuyo
    # path_regex no matchea FALLA ("no matching creation rules") —
    # cazado por el harness de la validación #4 corriendo desde un
    # workspace con .sops.yaml propio. /dev/shm no tiene ninguno:
    ( cd "$SECRETS_TMP" && \
      sops --encrypt --age "$AGE_PUBLIC" "$canary" > "$canary.enc" )
    printf '\nValidación REAL del resguardo: vas a pegar la key\n' >&2
    printf 'DESDE TU COPIA resguardada (no desde esta pantalla).\n' >&2
    printf 'Es la línea que empieza con AGE-SECRET-KEY-1...\n' >&2
    printf '(pegar: clic derecho o Ctrl+Shift+V; no se muestra).\n' >&2
    printf 'Plan B si el paste no anda: en OTRA terminal corré\n' >&2
    printf '  nano %s/age.restored\n' "$SECRETS_TMP" >&2
    printf 'pegá la línea, Ctrl+O + Enter, Ctrl+X, y acá dale Enter\n' >&2
    printf 'con el prompt vacío.\n\n' >&2
    local pasted
    read -rsp "pegá la AGE-SECRET-KEY desde tu resguardo: " pasted \
        || { log_warn "stdin cerrado en la validación del resguardo"; return 1; }
    echo >&2
    if [[ -n "$pasted" ]]; then
        printf '%s\n' "$pasted" > "$SECRETS_TMP/age.restored"
        unset pasted
    fi
    chmod 600 "$SECRETS_TMP/age.restored" 2>/dev/null
    [[ -s "$SECRETS_TMP/age.restored" ]] || {
        log_warn "no hay key pegada ni archivo (plan B)"; return 1; }
    SOPS_AGE_KEY_FILE="$SECRETS_TMP/age.restored" \
        sops -d "$canary.enc" | grep -q "aegis-init-canary-$$"
}
# (validate_cosign_backup ELIMINADO en D11: la ceremonia cosign no
# existe más — el keypair y la password viven en el store cifrado y
# se recuperan con la age key, el único irreducible.)
