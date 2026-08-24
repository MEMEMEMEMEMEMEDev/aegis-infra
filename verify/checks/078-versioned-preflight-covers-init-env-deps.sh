# title: the versioned preflight covers init's environment deps (W-02)
# origin: verify-static.sh (v2) ══ 78
check() {
D78=""
PF="$LIBEXEC/aegis-preflight"
if [[ -f "$PF" ]]; then
    bash -n "$PF" 2>/dev/null || D78="$D78 aegis-preflight.sh does not parse (bash -n);"
    # init ASSUMES the preflight left these things in place; if the
    # preflight stops covering one of them, the corresponding gate/phase
    # dies mid-run (and nobody would know why). They are nailed down here:
    #   /dev/shm         → the age ceremony (W-01) writes the key there
    #   registry-1.docker.io → the negativo-deny-by-default gate (W-04) pulls nginx
    #   tmux/jq/import yaml  → phase 00's bootstrap-bins gate + injection
    #   timedatectl      → the clock (TLS/ACME/cosign/apt)
    for dep in '/dev/shm' 'registry-1.docker.io' 'tmux' 'jq' 'import yaml' 'timedatectl'; do
        grep -qF -- "$dep" "$PF" \
            || D78="$D78 the preflight does not cover '$dep' (an init dep);"
    done
else
    D78="$D78 init/aegis-preflight.sh missing (versioned env-prep, W-02);"
fi
if [[ -n "$D78" ]]; then fail "preflight:$D78"
else pass "the preflight in init/ covers /dev/shm, docker.io, tmux, jq, pyyaml, the clock"; fi
}
