# teeth of check 030b (the secrets cleanup does not use rmdir)
# rmdir fails with subdirectories (docker/): the phase ends up FAILED
# with the work done, which is the worst outcome.
red_1() { printf '\n_bad_cleanup() { rmdir "$TMPDIR"; }\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
