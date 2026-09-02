# title: the tunnel is left with no connections before the teardown asks Cloudflare to delete it
# origin: new in v3 — 2026-09-02, measured tearing down the house instance for the definitive install
check() {
# MEASURED 2026-09-02. `aegis destroy --yes --k3s` could not succeed on
# a live instance, and never could:
#
#   · the edge is destroyed FIRST and the cluster LAST;
#   · so when tofu asks Cloudflare to delete the tunnel, cloudflared is
#     still running in the cluster this same command has not touched;
#   · Cloudflare refuses with «1022 This tunnel has active connections»;
#   · the `die` that followed ended the run, so `--k3s` never ran.
#
# What the operator got was a FATAL, an edge HALF destroyed —the CNAMEs
# are deleted before the tunnel, so every hostname is already dark— and
# no hint that the way out is to stop a Deployment they were not
# thinking about.
#
# And scaling to zero alone does not do it, which is the part that is
# easy to miss: ArgoCD's syncPolicy has selfHeal, so it puts the
# replica back. Measured while watching: the pod returned with a new
# name. The hand comes off the Application FIRST, and only then the
# Deployment goes to zero. That ORDER is the fix, and order is what
# this check measures.
#
# It is exercised, not read: the real function is extracted from the
# command and run against a kubectl that records what it was asked.
# A guard that exists and is never called, or called in the wrong
# order, passes any grep and fails here.
D183=""
DEST="$AEGIS_ROOT/libexec/aegis-destroy"
[[ -f "$DEST" ]] || { skip "there is no libexec/aegis-destroy: this check has no subject"; return; }

# (a) the guard is CALLED, and before the destroy that needs it.
_code() { grep -vE '^[[:space:]]*#' "$DEST"; }
L_CALL="$(_code | grep -n '_disconnect_tunnel$' | head -1 | cut -d: -f1)"
L_DESTROY="$(_code | grep -n 'destroy -auto-approve' | head -1 | cut -d: -f1)"
if [[ -z "$L_CALL" ]]; then
    D183="$D183 nothing calls _disconnect_tunnel: the guard can be perfect and the teardown still dies on a tunnel with connections;"
elif [[ -n "$L_DESTROY" ]] && (( L_CALL > L_DESTROY )); then
    D183="$D183 _disconnect_tunnel runs at line $L_CALL, AFTER the destroy at $L_DESTROY: disconnecting once the deletion already failed is not a precondition;"
fi

# (b) and it does the right things, in the right order, against a
#     kubectl that answers like a live cluster.
T="$(mktemp -d)"; LOG="$T/llamadas"
cat > "$T/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG_183"
case "$*" in
  "cluster-info")                      exit 0 ;;
  *"get deploy cloudflared"*)          exit 0 ;;
  *"get application cloudflare-tunnel"*) exit 0 ;;
  *"patch application"*)               exit 0 ;;
  *"scale deploy cloudflared"*)        exit 0 ;;
  *"get pods"*)
      n=$(grep -c 'get pods' "$LOG_183")
      # the pod is still there for the first two polls, then it is gone
      (( n <= 2 )) && echo "cloudflared-69867ddc88-b5lzd   1/1   Running   0   3m"
      exit 0 ;;
esac
exit 0
STUB
chmod +x "$T/kubectl"

FN="$(awk '/^_disconnect_tunnel\(\) \{/,/^\}/' "$DEST")"
if [[ -z "$FN" ]]; then
    D183="$D183 the command defines no _disconnect_tunnel: nothing stops cloudflared before the tunnel is deleted;"
else
    ( export LOG_183="$LOG" PATH="$T:$PATH"
      say() { :; }
      eval "$FN"
      _disconnect_tunnel ) >/dev/null 2>&1
    P="$(grep -n 'patch application' "$LOG" | head -1 | cut -d: -f1)"
    S="$(grep -n 'scale deploy cloudflared' "$LOG" | head -1 | cut -d: -f1)"
    W="$(grep -c 'get pods' "$LOG")"
    [[ -n "$S" ]] || D183="$D183 it never scales cloudflared down, so the tunnel keeps its connections;"
    if [[ -z "$P" ]]; then
        D183="$D183 it never takes ArgoCD's hand off the Application: selfHeal puts the replica back within seconds and the scale-down is undone;"
    elif [[ -n "$S" ]] && (( P > S )); then
        D183="$D183 it scales down at call $S and only disables selfHeal at $P: in that order ArgoCD has already healed what was just scaled;"
    fi
    (( W >= 2 )) || D183="$D183 it does not wait for the pod to actually go (only $W poll(s)): asking Cloudflare while the replica is still terminating is the same race that failed;"

    # (c) and on a host with NO cluster it has to be a quiet no-op.
    cat > "$T/kubectl" <<'STUB2'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG_183"
[[ "$*" == "cluster-info" ]] && exit 1
exit 0
STUB2
    chmod +x "$T/kubectl"; : > "$LOG"
    ( export LOG_183="$LOG" PATH="$T:$PATH"
      say() { :; }
      eval "$FN"
      _disconnect_tunnel ) >/dev/null 2>&1 \
      || D183="$D183 with no cluster reachable the guard fails instead of returning: a teardown on a host whose cluster is already gone must not die here;"
    grep -q 'patch application' "$LOG" \
      && D183="$D183 with no cluster reachable it still tries to patch an Application: it is talking to something that is not there;"
fi
rm -rf "$T"

printf '    order exercised against a stub cluster · call site checked in the real command\n'
if [[ -n "$D183" ]]; then fail "the teardown can ask Cloudflare to delete a tunnel that still has connections:$D183"
else pass "the teardown takes ArgoCD's hand off the Application, then scales cloudflared to zero, waits for the pod to be gone, and only then asks Cloudflare to delete the tunnel; with no cluster it is a quiet no-op"; fi
}
