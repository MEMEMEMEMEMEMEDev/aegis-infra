# title: the signature's scope is declared by LABEL, never by list (#14)
# origin: verify-static.sh (v2) ══ 88
check() {
# THE incident of 2026-07-27, and the one #52 found still alive in the
# seed on 2026-08-11.
#
# The signing ClusterPolicy scoped `namespaces: [org-personal]`.
# org-portafolio was created, something was deployed there, and that
# organization was born OUTSIDE the reach of signature verification.
# There was no error, no warning, nothing red: the policy simply was not
# looking at it. An unsigned public busybox was admitted and the whole
# board was green.
#
# A list of namespaces can only name what already exists. Every new
# organization is born outside by default, and "outside" is invisible.
# The label inverts that: each tenant's bundle carries it, so the
# coverage arrives with the organization.
#
# THIS CHECK DID NOT EXIST. The correction was made on the instance in
# #14 and the seed stayed two generations behind for fifteen days, with
# the hole open, because nothing compared MEANING — only the presence of
# files. It was discovered only by mutating the scope by hand and seeing
# that verify-static was still green.
D88=""
POL88="$P/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml"
if [[ ! -f "$POL88" ]]; then
    D88="$D88 the signing ClusterPolicy does not exist;"
else
python3 - "$POL88" "$P" <<'PY' || D88="$D88 (see the detail above);"
import sys, yaml, pathlib

pol, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
bad = []

policies = [d for d in yaml.safe_load_all(pol.open()) if d]
if not policies:
    print("    the ClusterPolicy has no documents"); sys.exit(1)

scope_labels = set()
rules = 0
for p in policies:
    for r in p.get("spec", {}).get("rules", []):
        if not r.get("verifyImages"):
            continue
        rules += 1
        for group in (r.get("match") or {}).get("any", []) + \
                     (r.get("match") or {}).get("all", []):
            res = group.get("resources") or {}
            # (1) a LIST of namespaces is the old model: whatever is not
            #     enumerated is born outside, and nobody finds out.
            if res.get("namespaces"):
                bad.append(f"rule '{r['name']}' scopes by a LIST of namespaces "
                           f"{res['namespaces']}: every new organization is born outside "
                           f"the signature's reach without a single signal")
            sel = (res.get("namespaceSelector") or {}).get("matchLabels") or {}
            for k, v in sel.items():
                scope_labels.add((k, v))
            if not res.get("namespaces") and not sel:
                bad.append(f"rule '{r['name']}' bounds NOTHING: neither a list nor a selector")

if rules == 0:
    bad.append("no rule with verifyImages: the check evaluated nothing")

# (2) and the selector's label has to be carried by SOME Namespace of
#     the artifact. A selector that matches nothing scopes to zero: the
#     same hole, dressed up as the new model.
if scope_labels:
    bearers = {}
    for f in root.rglob("*.y*ml"):
        try:
            docs = list(yaml.safe_load_all(f.open()))
        except Exception:
            continue
        for d in docs:
            # There is YAML in the artifact whose root is a LIST
            # (kustomize patches): d.get() blew up with AttributeError
            # and the check died red without having measured anything.
            if not isinstance(d, dict) or d.get("kind") != "Namespace":
                continue
            labels = (d.get("metadata") or {}).get("labels") or {}
            for kv in scope_labels:
                if labels.get(kv[0]) == kv[1]:
                    bearers.setdefault(kv, []).append(d["metadata"]["name"])
    for kv in sorted(scope_labels):
        if not bearers.get(kv):
            bad.append(f"the scope label {kv[0]}={kv[1]} is carried by NO "
                       f"Namespace of the artifact: the policy scopes to zero pods")
        else:
            print(f"    scope {kv[0]}={kv[1]} -> {sorted(bearers[kv])}", file=sys.stderr)

for m in bad:
    print(f"    {m}")
sys.exit(1 if bad else 0)
PY
fi
if [[ -n "$D88" ]]; then fail "signature scope:$D88"
else pass "the signature scopes by the aegis-tenants label and that label is carried by a real Namespace of the artifact"; fi
}
