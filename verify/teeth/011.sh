# dientes del check 011 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# el sujeto desaparece: si el check no lo nota, no lo estaba leyendo
rojo_1() { rm -f "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml"; }

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/values.yaml"; }
