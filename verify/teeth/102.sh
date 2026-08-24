# dientes del check 102 (todo comando de bash resuelve igual)
#
# La fase 05 instala /usr/local/bin/aegis como SYMLINK al producto.
# Sin readlink -f, AEGIS_ROOT sería /usr/local y el comando no
# encontraría ni sus fases ni sus libs — y el error hablaría de un
# archivo faltante, no de la resolución.
red_1() {
    grep -v 'readlink -f' "$AEGIS_ROOT/libexec/state/backup" > "$AEGIS_ROOT/libexec/state/backup.d" \
        && mv "$AEGIS_ROOT/libexec/state/backup.d" "$AEGIS_ROOT/libexec/state/backup"
}
# la instancia no se inventa: eso es de lib/paths.sh
red_2() { printf '\nAEGIS_HOME="$HOME/aegis"\n' >> "$AEGIS_ROOT/libexec/aegis-destroy"; }
# y el resolvedor tiene que ser UNO
red_3() { printf '\naegis_home() { echo /otro/lado; }\n' >> "$AEGIS_ROOT/lib/common.sh"; }
control_1() { printf '\n# comentario legitimo\n' >> "$AEGIS_ROOT/lib/access.sh"; }
