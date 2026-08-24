# title: the log() of the tofu wrapper goes to stderr
# origin: verify-static.sh (v2) ══ 14, part c — split in v3
check() {
# The callers capture READ subcommands with $() (output -raw
# tunnel_id in phase 25): if log() writes to stdout, the header gets
# glued to the value. Run #6, bug 3 — and the original 14a looked only
# at lib/, so the wrapper was left out of scope.
WRAP_BAD="$(grep -E '^log\(\)' "$P/tofu/tofu-apply.sh" | grep -v '>&2' || true)"
if [[ -n "$WRAP_BAD" ]]; then fail "log() of the tofu wrapper WITHOUT >&2 (it contaminates output -raw):"$'\n'"$WRAP_BAD"
else pass "log() of the tofu wrapper routes to stderr"; fi
}
