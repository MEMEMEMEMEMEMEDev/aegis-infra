# title: the four log functions route to stderr (definition)
# origin: verify-static.sh (v2) ══ 14, part a — split in v3
check() {
# If a log goes back to stdout, every gen_* function captured with $()
# gets contaminated — the FATAL bug of validation #1: the header glued
# to the value broke the ceremony of the age key.
LOGDEF_BAD="$(grep -E '^log_(info|ok|warn|error)\(\)' "$LIBS/common.sh" | grep -v '>&2' || true)"
if [[ -n "$LOGDEF_BAD" ]]; then fail "log_* WITHOUT >&2:"$'\n'"$LOGDEF_BAD"
else pass "log_* route to stderr (definition)"; fi
}
