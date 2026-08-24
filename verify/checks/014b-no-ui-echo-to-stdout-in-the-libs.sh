# title: no UI echo to stdout in the libs
# origin: verify-static.sh (v2) ══ 14, part b — split in v3
check() {
# The line breaks after `read -rsp` contaminated the returned value.
# The scope is widened in v3: the libs no longer live under init/, and
# libexec/ also has functions that others capture with $().
UI_BAD="$(grep -rn '; echo$\|; echo "' "$LIBS" | grep -v '>&2' || true)"
if [[ -n "$UI_BAD" ]]; then fail "UI echo without >&2 in libs:"$'\n'"$UI_BAD"
else pass "no UI echo to stdout in libs"; fi
}
