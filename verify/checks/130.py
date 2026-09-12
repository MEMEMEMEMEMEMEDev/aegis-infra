"""Check 130 — the traffic is attributed to the organization the
generator actually named.

THE COUPLING. traefik labels each series with the CRD service it routed
to, and for a tenant that name is built out of two things the generator
writes: the namespace (`org-<organization>`) and the IngressRoute
(`<organization>-ruteo`). traefik joins them:

    org-<organization>-<organization>-ruteo-<hash>@kubernetescrd

`aegis traffic` turns that back into a dimension with a regular
expression. Nothing links the two files: rename the route in the
generator and the expression keeps compiling, keeps returning rows, and
attributes traffic to nobody — or, worse, to the wrong organization.
Every panel would then be confidently wrong, with no error anywhere.

So the shapes are DERIVED from the generator and the expression is run
against them here, in python, with no cluster involved.
"""
import os
import re
import sys

ROOT = sys.argv[1]
ORG_PY = os.path.join(ROOT, "lib", "aegis", "org.py")
TRAFFIC = os.path.join(ROOT, "libexec", "aegis-traffic")


def code(path):
    try:
        return "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                         if not l.lstrip().startswith("#"))
    except OSError:
        return None


gen, traf = code(ORG_PY), code(TRAFFIC)
if gen is None or traf is None:
    print(f"SCOPE: {'lib/aegis/org.py' if gen is None else 'libexec/aegis-traffic'} is not "
          f"there — the coupling could not be read")
    sys.exit(0)

# What the generator names. Both derived, neither written down here.
ns_tpl = re.search(r'ns\s*=\s*f"(org-\{org\})"', gen)
# THE INGRESSROUTE'S name, and not the first `name: {org}-…` in the
# file: the generator writes a Middleware called `{org}-cabeceras` a few
# lines above, and the first version of this check derived THAT one and
# reported four false failures about a shape traefik never builds. The
# anchor is the kind.
route_tpl = re.search(r'kind:\s*IngressRoute\b.*?^\s*name:\s*\{org\}-([a-z0-9-]+)\s*$',
                      gen, re.M | re.S)
if not ns_tpl or not route_tpl:
    print("the generator's namespace or IngressRoute name could not be derived from "
          "lib/aegis/org.py: the shapes this check compares against are gone")
    sys.exit(0)
suffix = route_tpl.group(1)

# The matcher the command builds for ONE organization. It is a template
# in the source; here it is filled in and run against the label traefik
# would actually produce.
tpl = re.search(r"""return\s+f'service=~"([^"]+)"'""", traf)
if not tpl:
    print("libexec/aegis-traffic builds no exact `service` matcher per organization: the "
          "only other way to split that label is to guess, and the name appears twice in it")
    sys.exit(0)

# THE PROBES ARE CHOSEN, not sampled. `shop` and `shop-dev` are both
# valid names and one is a PREFIX of the other, which is the only shape
# where a loose matcher goes unnoticed: `org-shop-.*-ruteo.*` matches
# shop-dev's route perfectly well, and shop would quietly be credited
# with its neighbour's visitors. Without this pair the check passed over
# the exact bug it was written for — its own tooth said so.
probes = ["shop", "shop-dev", "portafolio", "a-b-c", "x12"]
for name in probes:
    label = f"org-{name}-{name}-{suffix}-9f3a2b@kubernetescrd"
    rx = tpl.group(1).replace("{org}", re.escape(name))
    if not re.fullmatch(rx, label):
        print(f"the matcher for {name!r} does not match {label!r}, which is exactly what "
              f"traefik builds from the generator's namespace and route: the panel would "
              f"show a zero, and a zero looks like a quiet day")
    # AND IT MATCHES NOBODY ELSE. `a` and `a-b-c` are both valid names,
    # and a loose matcher would credit one with the other's visitors.
    for other in probes:
        if other == name:
            continue
        theirs = f"org-{other}-{other}-{suffix}-9f3a2b@kubernetescrd"
        if re.fullmatch(rx, theirs):
            print(f"the matcher for {name!r} also matches {other!r}'s route: traffic would "
                  f"be credited to the wrong tenant, confidently and with no error anywhere")

# AND NOTHING DISAPPEARS. Per-organization plus platform does not cover
# everything — the canary's route has a tenant's shape and no contract —
# so the command asks for the total and names the remainder. Without
# that, requests stop existing silently, which is the quietest wrong
# there is.
# And it is asked of the REPORTING call, not of the string: `traffic:total`
# also appears in the branch that says the query failed, so grepping for
# the words vouched for a command that had stopped reporting the total
# entirely. Its own tooth deleted exactly that line and this stayed
# green.
reports_total = re.search(r'steps\.already\(\s*"traffic:total"', traf)
reports_rest = re.search(r'steps\.already\(\s*"traffic:unattributed"', traf)
if not reports_total or not reports_rest:
    print("libexec/aegis-traffic does not reconcile against the total: requests that belong "
          "to no listed organization and are not platform traffic would simply stop existing")

# And platform traffic is asked for with the NEGATION of the same shape,
# so that nothing is counted twice and nothing lands on a tenant that
# never received it.
if 'service!~"org-.*-ruteo.*"' not in traf:
    print("the platform's traffic is not asked for as the negation of the tenant shape: "
          "requests to argocd or jenkins could be summed into an organization, inventing "
          "visitors it never had")

print(f"SCOPE: the pattern checked against {len(probes)} route name(s) derived from the "
      f"generator (namespace org-<org>, route <org>-{suffix})")
