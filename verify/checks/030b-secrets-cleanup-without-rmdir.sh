# title: the secrets cleanup does not use rmdir
# origin: verify-static.sh (v2) ══ 30, part b — split in v3
check() {
# rmdir fails with subdirectories (docker/) → the phase ends up FAILED
# with the work done, which is the worst possible outcome (run #9).
if nc "$LIBS/secrets.sh" | grep -q 'rmdir'; then
    fail "secrets.sh uses rmdir (fails with subdirs such as docker/ — use rm -rf post-shred)"
else
    pass "secrets_cleanup without rmdir (rm -rf post-shred)"
fi
}
