# title: --from RE-RUNS the named phase even if it has a marker (run #11)
# origin: verify-static.sh (v2) ══ 34
check() {
# --from 15 with a previous marker skipped the phase asked for by name
# → the external resource deleted outside the init (webhook) was never
# recreated. The real mechanics are demanded on non-comment lines: the
# --from branch sets force_run=true and the skip by is_done reads it:
INIT_NC34="$(nc "$LIBEXEC/aegis-init")"
if echo "$INIT_NC34" | grep -q 'force_run=true' \
   && echo "$INIT_NC34" | grep 'is_done "\$name"' | grep -q 'force_run'; then
    pass "--from forces the re-run of the named phase (the marker does not skip it)"
else
    fail "aegis-init.sh: the --from phase can be skipped by its marker (run #11: deleted webhook never recreated)"
fi
}
