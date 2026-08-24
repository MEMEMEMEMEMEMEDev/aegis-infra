# title: el log() del wrapper de tofu va a stderr
# origen: verify-static.sh (v2) ══ 14, parte c — partida en v3
check() {
# Los callers capturan subcomandos de LECTURA con $() (output -raw
# tunnel_id en la fase 25): si log() escribe a stdout, el header se
# pega al valor. Corrida #6, bug 3 — y el 14a original miraba solo
# lib/, así que el wrapper quedaba fuera de alcance.
WRAP_BAD="$(grep -E '^log\(\)' "$P/tofu/tofu-apply.sh" | grep -v '>&2' || true)"
if [[ -n "$WRAP_BAD" ]]; then fail "log() del wrapper de tofu SIN >&2 (contamina output -raw):"$'\n'"$WRAP_BAD"
else pass "log() del wrapper de tofu rutea a stderr"; fi
}
