# titulo: preflight versionado cubre las deps de entorno del init (W-02)
# origen: verify-static.sh (v2) ══ 78
check() {
D78=""
PF="$LIBEXEC/aegis-preflight"
if [[ -f "$PF" ]]; then
    bash -n "$PF" 2>/dev/null || D78="$D78 aegis-preflight.sh no parsea (bash -n);"
    # el init ASUME que el preflight dejó estas cosas; si el preflight
    # deja de cubrir una, el gate/fase correspondiente muere en la
    # corrida (y nadie sabría por qué). Las clava acá:
    #   /dev/shm         → ceremonia age (W-01) escribe la clave ahí
    #   registry-1.docker.io → gate negativo-deny-by-default (W-04) pulea nginx
    #   tmux/jq/import yaml  → gate bootstrap-bins de la fase 00 + inyección
    #   timedatectl      → reloj (TLS/ACME/cosign/apt)
    for dep in '/dev/shm' 'registry-1.docker.io' 'tmux' 'jq' 'import yaml' 'timedatectl'; do
        grep -qF -- "$dep" "$PF" \
            || D78="$D78 el preflight no cubre '$dep' (dep del init);"
    done
else
    D78="$D78 falta init/aegis-preflight.sh (env-prep versionado, W-02);"
fi
if [[ -n "$D78" ]]; then fail "preflight:$D78"
else pass "preflight en init/ cubre /dev/shm, docker.io, tmux, jq, pyyaml, reloj"; fi
}
