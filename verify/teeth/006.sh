# dientes del check 006 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# el sujeto desaparece: si el check no lo nota, no lo estaba leyendo
red_1() { rm -f "$AEGIS_ROOT/init/phases/30-argocd.sh"; }

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/30-argocd.sh"; }
