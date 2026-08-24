# titulo: --from/--only con fase inexistente = error duro (corrida #10)
# origen: verify-static.sh (v2) ══ 32
check() {
# un nombre que no matchea ninguna fase hacía skipear TODO el loop y
# reportar "completas" — falso 'todo listo'. Se exige la validación
# REAL (llamadas a phase_exists sobre ambas flags, no-comentario),
# no la mención en un comentario:
# sesión 21 (P3 auditoría): la validación subió de existencia a
# UNICIDAD — phase_check_unique muere también con prefijo AMBIGUO
# ('--from 1' matcheaba 10/12/15 y arrancaba en la 10 sin aviso):
INIT_NC="$(nc "$LIBEXEC/aegis-init")"
if echo "$INIT_NC" | grep -q 'phase_check_unique --from "\$FROM_PHASE"' \
   && echo "$INIT_NC" | grep -q 'phase_check_unique --only "\$ONLY_PHASE"' \
   && echo "$INIT_NC" | grep -q 'fase desconocida' \
   && echo "$INIT_NC" | grep -q 'AMBIGUO'; then
    pass "--from y --only validados contra PHASES: inexistente Y ambiguo abortan"
else
    fail "aegis-init.sh NO valida --from/--only (existencia + unicidad) contra las fases reales"
fi
}
