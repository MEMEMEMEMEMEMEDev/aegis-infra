# title: placeholders: all with a declared owner
# origin: verify-static.sh (v2) ══ 3
check() {
# config-class (owner: render_platform_placeholders — phase 10 on a
# virgin start and phase 85 after bringing files from the seed; the 5
# observability ones are DERIVED from \$PROFILE, table in common.sh) +
# generated-class (owners: phase 10 AGE_PUBLIC, phase 80
# COSIGN_PUB/AEGIS_CA_PEM, phase 85 OBS_CA_PEM and the 2 bcrypt hashes
# of ntfy) + vps-class (owner: `aegis vps render`, which builds the
# lab's user-data in /dev/shm: CF_TUNNEL_TOKEN and the operator's two
# public keys — checks 94/95).
#
# The fourth class is template-class and it is NOT written here: it is
# DERIVED from `aegis app`, which is its only owner (_values_for).
# Writing it by hand would be a second source of truth, and the day the
# template asks for something new the check would lie in the
# comfortable direction.
#
# The sweep covers ALL of seed/ and goes by CONTENT, not by extension:
# on 2026-08-24 this check swept only seed/platform/ and only
# yaml/yml/tf/tpl, so the templates (from which each app's repo is
# born: go.mod, main.go, Containerfile, README.md) had nobody looking
# at them. It is the same blindness by extension as check 1.
#
# Any other __X__ = orphan placeholder = FAIL.
TEMPLATE_OWNER="$AEGIS_ROOT/libexec/aegis-app"
if [[ ! -r "$TEMPLATE_OWNER" ]]; then
    skip "cannot derive template-class: $(basename "$TEMPLATE_OWNER") is missing"
    return
fi
TEMPLATE_VALUES="$(grep -o '"__[A-Z0-9_]\+__":' "$TEMPLATE_OWNER" \
  | tr -d '":' | sort -u)"
if [[ -z "$TEMPLATE_VALUES" ]]; then
    skip "cannot derive template-class: $(basename "$TEMPLATE_OWNER") declares no template values"
    return
fi
TEMPLATE_CLASS="$(printf '%s\n' $TEMPLATE_VALUES | sed -e 's/^__//' -e 's/__$//' | paste -sd'|')"

# The config class is DERIVED from its owner too, and for the same
# reason as the template class: until 2026-08-26 the same names lived
# written by hand here, in lib/common.sh (_CONFIG_PLACEHOLDERS) and in
# check 074's dummy renderer — three copies, so adding a placeholder to
# two of them left this check approving an orphan, or failing over one
# that has a perfectly good owner.
CONFIG_OWNER="$LIBS/common.sh"
CONFIG_CLASS="$(sed -n "s/^_CONFIG_PLACEHOLDERS='__.\\(\\(.*\\)\\)__'\$/\\1/p" "$CONFIG_OWNER" \
    | tr -d '\\\\' | sed 's/^(//; s/)$//')"
if [[ -z "$CONFIG_CLASS" ]]; then
    skip "cannot derive config-class: _CONFIG_PLACEHOLDERS not readable in $(basename "$CONFIG_OWNER")"
    return
fi
ORPHANS="$(grep -rhoI '__[A-Z0-9_]\+__' "$SEED" 2>/dev/null \
  | sort -u \
  | grep -v -E "^__($TEMPLATE_CLASS)__\$" \
  | grep -v -E "^__($CONFIG_CLASS)__\$" \
  | grep -v -E '^__(AGE_PUBLIC|COSIGN_PUB|AEGIS_CA_PEM|OBS_CA_PEM|OBS_NTFY_OPERADOR_HASH|OBS_NTFY_PUENTE_HASH|CF_TUNNEL_TOKEN|SSH_PUBKEY_RSA|SSH_PUBKEY_ED25519)__$' \
  || true)"
if [[ -n "$ORPHANS" ]]; then fail "placeholders with no owner: $ORPHANS"
else pass "placeholders: all with an owner (config, generated, vps or template — the last one derived from $(basename "$TEMPLATE_OWNER"))"; fi
}
