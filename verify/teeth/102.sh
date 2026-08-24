# teeth for check 102 (every bash command resolves alike)
#
# Phase 05 installs /usr/local/bin/aegis as a SYMLINK to the product.
# Without readlink -f, AEGIS_ROOT would be /usr/local and the command
# would find neither its phases nor its libs — and the error would talk
# about a missing file, not about the resolution.
red_1() {
    grep -v 'readlink -f' "$AEGIS_ROOT/libexec/state/backup" > "$AEGIS_ROOT/libexec/state/backup.d" \
        && mv "$AEGIS_ROOT/libexec/state/backup.d" "$AEGIS_ROOT/libexec/state/backup"
}
# the instance is not invented: that belongs to lib/paths.sh
red_2() { printf '\nAEGIS_HOME="$HOME/aegis"\n' >> "$AEGIS_ROOT/libexec/aegis-destroy"; }
# and the resolver has to be ONE
red_3() { printf '\naegis_home() { echo /somewhere/else; }\n' >> "$AEGIS_ROOT/lib/common.sh"; }
control_1() { printf '\n# legitimate comment\n' >> "$AEGIS_ROOT/lib/access.sh"; }
