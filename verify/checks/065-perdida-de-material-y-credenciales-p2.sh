# titulo: pérdida de material y credenciales (P2 auditoría)
# origen: verify-static.sh (v2) ══ 65
check() {
D65=""
PS65="$(body_of persist_secret "$LIBS/secrets.sh")"
echo "$PS65" | grep -q '\.enc\.tmp' \
    || D65="$D65 persist_secret trunca el .enc ANTES de sops (fallo = ciphertext previo en 0 bytes);"
echo "$PS65" | grep -q 'mv .*\.enc\.tmp' \
    || D65="$D65 persist_secret sin mv atómico post-roundtrip;"
GK65="$(body_of gen_or_restore_keypair "$LIBS/secrets.sh")"
echo "$GK65" | grep -q 'ssh-keygen -y' \
    || D65="$D65 falta .pub ⇒ regeneraría el PAR entero (desincroniza la deploy key viva);"
CB65="$(body_of ceremony_backup "$LIBS/secrets.sh")"
# W-01/EV-01 (2026-07-21): la ceremonia NO imprime la clave al pane en
# interactivo. tmux pipe-pane, script(1) y los transcripts de agentes
# graban el pane, y [[ -t 1 ]] no detecta la clase (bajo tmux stdout
# SIGUE siendo un TTY). El valor va a tmpfs y se lee desde OTRA terminal.
echo "$CB65" | nc | grep -Eq 'cat +"\$file"' \
    && D65="$D65 la ceremonia imprime la age key al pane (cat del archivo) — se graba en tmux/script/transcript;"
echo "$CB65" | grep -q '/dev/shm/aegis-resguardo' \
    || D65="$D65 la ceremonia interactiva no usa el camino tmpfs (resguardo leído desde otra terminal);"
nc "$FASES/15-terceros.sh" | grep -q 'x-oauth-scopes' \
    || D65="$D65 el gh token se hornea como credencial de CI sin gate de scopes reales;"
grep -q 'ya existe — skip' "$FASES/30-argocd.sh" \
    && D65="$D65 la 30 sigue con skip-if-exists (material rotado queda stale en el cluster);"
nc "$FASES/30-argocd.sh" | grep -q 'gen_or_restore redis_auth' \
    || D65="$D65 el password de redis no sale del store (apply convergente lo rotaría por corrida);"
PF65="$(body_of _jenkins_pass_file "$LIBS/jenkins.sh")"
echo "$PF65" | grep -q 'umask 077' \
    || D65="$D65 el password file de jenkins nace 644 (ventana antes del chmod);"
if [[ -n "$D65" ]]; then fail "material:$D65"
else pass "store atómico, pub derivada (no regenerada), ceremonia por tmpfs (no imprime al pane), scopes gateados, bootstrap convergente"; fi
}
