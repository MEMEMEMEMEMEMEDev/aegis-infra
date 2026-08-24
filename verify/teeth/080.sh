# teeth for check 080 (backup/restore of the three states)
#
# The three states that live only on this machine: the encrypted store,
# the phase markers and the edge's tfstate. Losing one forces redoing
# the installation by hand — and the age key does NOT recover them.
#
# (The automatically generated red pointed at libexec/aegis-backup; the
# rename to `aegis state backup` left it pointing at a file that no
# longer exists, and the full teeth run reported it as «the tooth is
# broken, not the check». That the mechanism detects its own rotten
# pieces is half the point.)
red_1() {
    grep -vE "name 'aegis.key'|sops/age" "$AEGIS_ROOT/libexec/state/backup" > "$AEGIS_ROOT/libexec/state/backup.d" \
        && mv "$AEGIS_ROOT/libexec/state/backup.d" "$AEGIS_ROOT/libexec/state/backup"
}
red_2() { grep -v 'force' "$AEGIS_ROOT/libexec/state/restore" > "$AEGIS_ROOT/libexec/state/restore.d" \
        && mv "$AEGIS_ROOT/libexec/state/restore.d" "$AEGIS_ROOT/libexec/state/restore"; }
control_1() { printf '\n# legitimate comment\n' >> "$AEGIS_ROOT/libexec/state/backup"; }
