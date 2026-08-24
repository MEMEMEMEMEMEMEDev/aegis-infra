# titulo: modo DESATENDIDO completo (P0 auditoría 2026-07-18)
# origen: verify-static.sh (v2) ══ 62
check() {
# el diseño asumía operador presente: 9+ prompts sin bypass, wizard
# con busy-loop infinito con stdin cerrado, secretos solo por prompt.
D62=""
nc "$LIBEXEC/aegis-init" | grep -q -- '--non-interactive)' \
    || D62="$D62 aegis-init.sh sin flag --non-interactive;"
nc "$LIBEXEC/aegis-init" | grep -q -- '! -t 0' \
    || D62="$D62 sin guard temprano de TTY (sin terminal moría en el primer read, a minutos de camino);"
HS62="$(body_of human_step "$LIBS/common.sh")"
echo "$HS62" | grep -q 'ni_mode' || D62="$D62 human_step no honra el modo desatendido;"
GR62="$(body_of gate_red "$LIBS/common.sh")"
echo "$GR62" | grep -q 'ni_mode' || D62="$D62 gate_red no honra el modo desatendido;"
ASK62="$(body_of ask "$LIBS/config.sh")"
echo "$ASK62" | grep -q 'stdin cerrado' \
    || D62="$D62 ask() sin corte por EOF (busy-loop infinito con stdin cerrado);"
echo "$ASK62" | grep -q 'tries' \
    || D62="$D62 ask() sin tope de intentos inválidos;"
nc "$LIBS/config.sh" | grep -q 'ni_mode && die' \
    || D62="$D62 ensure_config no exige conf pre-hecho en desatendido;"
nc "$FASES/15-terceros.sh" | grep -q 'CF_MASTER_FILE' \
    || D62="$D62 fase 15 sin camino por archivo para la maestra CF;"
nc "$LIBS/secrets.sh" | grep -q 'AEGIS_AGE_BACKUP_FILE' \
    || D62="$D62 ceremonia sin camino por archivo para el resguardo age;"
nc "$FASES/12-workrepos.sh" | grep -q 'ni_mode && die' \
    || D62="$D62 repo sin marcador se auto-confirmaría en desatendido (pisaría un repo real con push --force);"
ABS62="$(body_of ansible_become_setup "$LIBS/common.sh")"
echo "$ABS62" | grep -q 'ni_mode && die' \
    || D62="$D62 become sin NOPASSWD colgaría pidiendo password en desatendido;"
if [[ -n "$D62" ]]; then fail "modo desatendido:$D62"
else pass "desatendido de punta a punta: flag+TTY guard, wizard acotado, secretos por archivo, ROJO con excepción de repos ajenos"; fi
}
