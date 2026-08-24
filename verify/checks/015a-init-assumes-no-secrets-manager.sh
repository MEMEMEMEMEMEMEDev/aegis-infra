# title: D11 — the init assumes no particular secrets manager
# origin: verify-static.sh (v2) ══ 15, part a — split in v3
check() {
# D11 (total automation): the operator has no reason to use the
# manager the author used. A prompt that names a particular one turns a
# preference into a requirement.
#
# The scope CHANGES in v3 and it is a textbook case: in v2 the
# exclusion was `--exclude=verify-static.sh`, by FILE NAME. When the
# verifier was split into 96 files that exclusion stopped excluding
# anything, and this check would have started biting the comments of
# its own siblings (H7 of the record: filters by name die silently when
# the file is split). The DIRECTORY is excluded.
BW="$(grep -rn 'Bitwarden' "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" \
      --exclude-dir=verify --exclude-dir=__pycache__ || true)"
if [[ -n "$BW" ]]; then fail "mentions of a particular manager:"$'\n'"$BW"
else pass "agnostic prompts (no manager assumed)"; fi
}
