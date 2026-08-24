# title: the cluster-admin kubeconfig is not born world-readable
# origin: verify-static.sh (v2) ══ 85
check() {
# Run on native Linux (2026-07-25): k3s was installed with
# --write-kubeconfig-mode 644 and /etc/rancher/k3s/k3s.yaml carries the
# CLUSTER-ADMIN client-certificate + client-key. At 644 any local user
# or process on the host takes the whole cluster. On the disposable VM
# it was irrelevant; on a real host it is direct escalation.
# The mode and the COPY are coupled: at 600 root:root, the user-level
# `cp` phase 20 used to do stops working. This check nails both sides
# together — lowering only one breaks the phase, and that is exactly
# the mistake that invites "fixing it" by going back to 644.
D85=""
GV85="$P/ansible/inventory/group_vars/all.yml"
# the '\' continuations are joined BEFORE grepping: otherwise a
# `sudo install ... \` + path on the next line reads as an unprivileged
# copy (a false positive this very check produced as it was written —
# narrowness is the verifier's chronic disease).
F20="$(sed -e :a -e '/\\$/N; s/\\\n[[:space:]]*//; ta' "$PHASES/20-k3s.sh" \
       | nc)"
MODE85="$(grep -oE '\-\-write-kubeconfig-mode[= ]+0?[0-7]{3}' "$GV85" 2>/dev/null \
          | grep -oE '0?[0-7]{3}$' | tail -1)"
if [[ -z "$MODE85" ]]; then
    D85="$D85 cannot find --write-kubeconfig-mode in group_vars (was the flag renamed? the check would go blind);"
else
    # the group and other bits MUST be 0: only the owner reads the credential
    if [[ "${MODE85: -2}" != "00" ]]; then
        D85="$D85 --write-kubeconfig-mode $MODE85 leaves the cluster-admin kubeconfig readable by group/others;"
    fi
fi
# the other side of the coupling: the root:root 600 copy of the
# kubeconfig CANNOT be made without privilege.
CP85="$(printf '%s\n' "$F20" | grep -E '/etc/rancher/k3s/k3s\.yaml')"
if [[ -z "$CP85" ]]; then
    D85="$D85 phase 20 no longer copies /etc/rancher/k3s/k3s.yaml (the check went blind to the coupling);"
elif ! printf '%s\n' "$CP85" | grep -q 'sudo'; then
    D85="$D85 phase 20 copies the kubeconfig WITHOUT privilege — with mode $MODE85 at the source that copy fails;"
fi
printf '%s\n' "$F20" | grep -qE 'chmod\s+6?00\s+"?\$HOME/\.kube/config|install -m\s*600' \
    || D85="$D85 ~/.kube/config does not end up with an explicit mode 600 in phase 20;"
if [[ -n "$D85" ]]; then fail "kubeconfig:$D85"
else pass "cluster-admin kubeconfig with mode $MODE85 and copied with privilege to ~/.kube/config 600"; fi
}
