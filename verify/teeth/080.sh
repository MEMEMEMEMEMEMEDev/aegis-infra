# dientes del check 080 (backup/restore de los tres estados)
#
# Los tres estados que solo viven en esta máquina: el store cifrado,
# los markers de fases y el tfstate del borde. Perder uno obliga a
# rehacer la instalación a mano — y la age key NO los recupera.
#
# (El rojo generado automáticamente apuntaba a libexec/aegis-backup;
# el renombre a `aegis state backup` lo dejó apuntando a un archivo
# que ya no existe, y la corrida completa de dientes lo denunció como
# «el diente está roto, no el check». Que el mecanismo detecte sus
# propias piezas podridas es la mitad del punto.)
rojo_1() {
    grep -vE "name 'aegis.key'|sops/age" "$AEGIS_ROOT/libexec/state/backup" > "$AEGIS_ROOT/libexec/state/backup.d" \
        && mv "$AEGIS_ROOT/libexec/state/backup.d" "$AEGIS_ROOT/libexec/state/backup"
}
rojo_2() { grep -v 'force' "$AEGIS_ROOT/libexec/state/restore" > "$AEGIS_ROOT/libexec/state/restore.d" \
        && mv "$AEGIS_ROOT/libexec/state/restore.d" "$AEGIS_ROOT/libexec/state/restore"; }
control_1() { printf '\n# comentario legitimo\n' >> "$AEGIS_ROOT/libexec/state/backup"; }
