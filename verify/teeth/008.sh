# dientes del check 008 (gates que no pueden fallar)
# Un gate que se traga su propio resultado es peor que no tener gate:
# da la sensación de estar midiendo.
red_1() { printf '\ngate "siempre-verde" kubectl get nodes || true\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
red_2() { printf '\ngate "otro-verde" kubectl get nodes ; true\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
