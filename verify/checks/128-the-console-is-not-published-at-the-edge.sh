# title: the console is not published at the edge, and it binds loopback and nothing else
# origin: new in v3 — 2026-09-11, D2 of plan/15: the console CANNOT go behind Access the way Jenkins does
check() {
# WHY THIS CHECK EXISTS INSTEAD OF AN ACCESS APPLICATION.
#
# The plan said the console would sit behind Cloudflare Access under the
# cloudflare profile, «the same door Jenkins and ArgoCD go through».
# Measured on 2026-09-11, that door does not reach it, and the reason is
# structural rather than a missing line:
#
#   · the tunnel has ONE ingress_service for every hostname —
#     `http://traefik.infra-edge.svc.cluster.local:80` (tofu/envs/
#     cloudflare-tunnel/main.tf) — so everything published arrives at
#     traefik and needs an IngressRoute to a Service;
#   · cloudflared runs IN THE CLUSTER (k8s/base/ingress/cloudflare-
#     tunnel/cloudflared.yaml, a Deployment in infra-edge);
#   · and the console runs on the HOST, because what it executes needs
#     the age key, the `gh` session and kubectl — which is the whole
#     reason the plan put it there.
#
# A connector in the cluster cannot reach the host's loopback. Running a
# SECOND connector on the host does not fix it either: connectors of one
# tunnel are interchangeable and Cloudflare spreads requests across
# them, so a request would land on the cluster one, which still cannot
# reach 127.0.0.1. Publishing the console therefore means a tunnel of
# its own, with its own token to rotate and its own thing to watch —
# real cost, for a page only the operator reads, who already has ssh.
#
# So the console is NOT published, and that is a decision with a shape
# this check keeps:
#   1. no label of the platform's doors names it — a hostname added to
#      edge.yaml would create the CNAME and the tunnel rule, and then
#      traefik would 404 while the name resolves and TLS works, which is
#      the worst kind of broken;
#   2. it binds 127.0.0.1 and there is no flag to change that. The way
#      in is `ssh -L 7391:127.0.0.1:7391 <host>`.
#
# The day it should be published, the design is a connector on the host
# with its own tunnel — written down here so the next person does not
# rediscover the load-balancing part the hard way.
D128=""
BIN128="$LIBEXEC/aegis-console"
[[ -f "$BIN128" ]] || { skip "there is no console command yet: nothing to publish or to bind"; return; }

# 1 · the platform's doors do not name it.
EDGE128="$P/edge.yaml"
if [[ -f "$EDGE128" ]]; then
    if nc "$EDGE128" | grep -qE '^\s*-\s*console\s*$'; then
        D128="$D128 seed/platform/edge.yaml publishes a door called \`console\`: that creates the CNAME and the tunnel rule, and the connector in the cluster cannot reach a service on the host — the name would resolve, TLS would work, and traefik would answer 404;"
    fi
else
    D128="$D128 $EDGE128 does not exist and the platform's doors could not be read;"
fi

# 2 · it binds loopback, and the address is not a variable somebody can
#     pass. A flag here is one keystroke away from publishing everything
#     the round can see, on a page with no door of its own.
BODY128="$(nc "$BIN128")"
if ! grep -qF '("127.0.0.1", port)' <<<"$BODY128"; then
    D128="$D128 aegis-console does not bind the literal 127.0.0.1: the address became something that can be passed in, and this page has no login of its own;"
fi
if grep -qE '"0\.0\.0\.0"|--bind|--host\b|--address' <<<"$BODY128"; then
    D128="$D128 aegis-console offers a way to choose the bind address: that is the keystroke this design removed on purpose;"
fi

printf '    the console binds loopback; the platform publishes %s door(s)\n' \
    "$(nc "$EDGE128" 2>/dev/null | grep -cE '^\s*-\s+' || echo '?')"
if [[ -n "$D128" ]]; then
    fail "the console is reachable from somewhere it cannot serve:$D128"
else
    pass "no door of the platform names the console, and it binds 127.0.0.1 with no way to change it (ssh -L is the way in)"
fi
}
