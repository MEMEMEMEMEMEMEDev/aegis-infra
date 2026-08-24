# dientes del check 005b (argo_sync ↔ Applications declaradas)
# La clase del hueco hello-aegis: una fase sincroniza una App que
# nadie declara. El sync «no falla»: espera algo que no existe y se
# rinde por timeout, con un mensaje que habla de ArgoCD y no del
# manifiesto que falta.
red_1() { printf '\nargo_sync app-que-nadie-declara\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
control_1() { printf '\n# argo_sync app-que-nadie-declara (ejemplo en un comentario)\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
