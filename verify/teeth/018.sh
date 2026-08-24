# dientes del check 018 (acoplamiento temporal: entries ↔ fase de sync)
#
# Corrida #4, el bug que frenó la fase 35: un entry estático cuyo
# .enc.yaml se genera en una fase POSTERIOR al primer sync de su App
# rompe el build ATÓMICO de kustomize, y entonces NINGÚN secret de esa
# App se crea — ni los que sí existen. El síntoma aparece lejos de la
# causa, en otra fase y con otro nombre.
#
# Invariante: fase-productora(entry) ≤ fase-del-primer-argo_sync(App).
# Para violarlo hacen falta LAS DOS MITADES: el entry en el generator
# Y un productor tardío. Con el entry solo, el check lo trata como
# «lo produce el camino de contratos» y sigue — que es correcto, y por
# eso el primer intento de este diente no mordía.
rojo_1() {
    sed -i 's|^  - secret-github-webhook.enc.yaml.*|  - secret-tardio.enc.yaml\n&|' \
        "$AEGIS_ROOT/semilla/plataforma/k8s/base/platform/argocd-secrets/secret-generator.yaml"
    printf '\nmake_enc_secret "$PLATFORM_DIR/k8s/base/platform/argocd-secrets/secret-tardio.enc.yaml"\n' \
        >> "$AEGIS_ROOT/init/phases/80-supply-chain.sh"
}
