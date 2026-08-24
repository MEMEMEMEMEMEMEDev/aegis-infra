# dientes del check 089 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# el sujeto desaparece: si el check no lo nota, no lo estaba leyendo
rojo_1() { rm -f "$AEGIS_ROOT/libexec/aegis-rotate"; }

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/00-preflight.sh"; }
