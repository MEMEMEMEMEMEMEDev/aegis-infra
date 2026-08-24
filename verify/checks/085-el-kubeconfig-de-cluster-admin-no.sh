# titulo: el kubeconfig de cluster-admin no nace world-readable
# origen: verify-static.sh (v2) ══ 85
check() {
# Corrida en Linux nativo (2026-07-25): k3s se instalaba con
# --write-kubeconfig-mode 644 y /etc/rancher/k3s/k3s.yaml lleva el
# client-certificate + client-key de CLUSTER-ADMIN. Con 644 cualquier
# usuario o proceso local del host toma el cluster entero. En la VM
# desechable era irrelevante; en un host real es escalada directa.
# El modo y la COPIA están acoplados: con 600 root:root, el `cp` de
# usuario que hacía la fase 20 deja de funcionar. Este check clava los
# dos lados juntos — bajar uno solo rompe la fase, y ese es justo el
# error que invita a "arreglarlo" volviendo a 644.
D85=""
GV85="$P/ansible/inventory/group_vars/all.yml"
# las continuaciones con '\' se unen ANTES de grepear: si no, un
# `sudo install ... \` + ruta en la línea siguiente se lee como copia
# sin privilegio (falso positivo que este mismo check produjo al
# escribirse — la angostura es la enfermedad crónica del verificador).
F20="$(sed -e :a -e '/\\$/N; s/\\\n[[:space:]]*//; ta' "$FASES/20-k3s.sh" \
       | nc)"
MODE85="$(grep -oE '\-\-write-kubeconfig-mode[= ]+0?[0-7]{3}' "$GV85" 2>/dev/null \
          | grep -oE '0?[0-7]{3}$' | tail -1)"
if [[ -z "$MODE85" ]]; then
    D85="$D85 no encuentro --write-kubeconfig-mode en group_vars (¿se renombró el flag? el check quedaría ciego);"
else
    # bits de grupo y otros DEBEN ser 0: solo el dueño lee la credencial
    if [[ "${MODE85: -2}" != "00" ]]; then
        D85="$D85 --write-kubeconfig-mode $MODE85 deja el kubeconfig de cluster-admin legible por grupo/otros;"
    fi
fi
# el otro lado del acople: la copia del kubeconfig root:root 600 NO
# puede hacerse sin privilegio.
CP85="$(printf '%s\n' "$F20" | grep -E '/etc/rancher/k3s/k3s\.yaml')"
if [[ -z "$CP85" ]]; then
    D85="$D85 la fase 20 ya no copia /etc/rancher/k3s/k3s.yaml (el check quedó ciego al acople);"
elif ! printf '%s\n' "$CP85" | grep -q 'sudo'; then
    D85="$D85 la fase 20 copia el kubeconfig SIN privilegio — con modo $MODE85 en el origen esa copia falla;"
fi
printf '%s\n' "$F20" | grep -qE 'chmod\s+6?00\s+"?\$HOME/\.kube/config|install -m\s*600' \
    || D85="$D85 ~/.kube/config no queda con modo 600 explícito en la fase 20;"
if [[ -n "$D85" ]]; then fail "kubeconfig:$D85"
else pass "kubeconfig de cluster-admin con modo $MODE85 y copiado con privilegio a ~/.kube/config 600"; fi
}
