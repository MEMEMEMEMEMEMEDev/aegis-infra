# teeth of check 008 (gates that cannot fail)
# A gate that swallows its own result is worse than having no gate: it
# gives the feeling of measuring.
red_1() { printf '\ngate "always-green" kubectl get nodes || true\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
red_2() { printf '\ngate "another-green" kubectl get nodes ; true\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
