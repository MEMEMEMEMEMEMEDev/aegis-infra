# title: AppProjects: zero default + tenant without cluster-scoped (W-06 / R1-B)
# origin: verify-static.sh (v2) ══ 76
check() {
D76=""
APDIR="$P/k8s/argocd-apps"
APROJ="$P/k8s/bootstrap/appprojects.yaml"
# 1) no Application on project:default — ACROSS ALL of platform/k8s
#    (NOT only argocd-apps: the canary is ALSO defined in bundle.yaml —
#    the original check's narrow scope, class C15):
DEF76="$(grep -rln 'kind: Application' "$P/k8s" 2>/dev/null \
         | xargs -r grep -l 'project:[[:space:]]*default' 2>/dev/null)"
[[ -z "$DEF76" ]] || D76="$D76 Applications on project:default: $DEF76;"
# 2) the 3 AppProjects exist
for p in aegis-bootstrap aegis-platform aegis-tenant-canary; do
    grep -q "name: $p" "$APROJ" 2>/dev/null || D76="$D76 AppProject $p missing;"
done
# 3) INVARIANT R1-B: the tenant's project DENIES cluster-scoped
#    (an empty clusterResourceWhitelist) — the invariant, not a string:
TEN76="$(awk '/name: aegis-tenant-canary/,0' "$APROJ")"
echo "$TEN76" | grep -Eq 'clusterResourceWhitelist:[[:space:]]*\[\]' \
    || D76="$D76 aegis-tenant-canary does not deny cluster-scoped (clusterResourceWhitelist must be []);"
# aegis-platform uses namespace '*' (the charts create RBAC outside their
# ns — cert-manager in kube-system; enumerating = whack-a-mole every run, v1):
PLAT76="$(awk '/name: aegis-platform/,/name: aegis-tenant-canary/' "$APROJ")"
echo "$PLAT76" | grep -qF "namespace: '*'" \
    || D76="$D76 aegis-platform does not use namespace '*' (it was re-narrowed — the charts break the sync);"
# 4) the canary runs under a TENANT project and not under the platform
#    one. What matters is the project, NOT which file the App is
#    declared in: until 2026-07-28 this sub-check looked only at
#    ci-supply-tenants.yaml, and when the App moved into its
#    organization's bundle —which is where the single owner lives— it
#    gave a FAIL without the invariant having been broken. The same
#    class C15 that already forced sub-check 1 to be widened: a check
#    tied to LOCATION lies as soon as something moves. It is searched
#    across all of platform/k8s:
grep -rq 'project:[[:space:]]*aegis-tenant-canary' "$P/k8s" 2>/dev/null \
    || D76="$D76 no App in aegis-tenant-canary (the canary stayed in the platform project);"
# 5) phase 35 applies the AppProjects BEFORE root (class C1)
L_AP="$(grep -n 'appprojects.yaml' "$PHASES/35-gitops.sh" | head -1 | cut -d: -f1)"
L_ROOT="$(grep -n 'argocd-apps/root.yaml' "$PHASES/35-gitops.sh" | head -1 | cut -d: -f1)"
if [[ -z "$L_AP" || -z "$L_ROOT" ]] || (( L_AP > L_ROOT )); then
    D76="$D76 phase 35 does not apply the AppProjects before root (or it is missing);"
fi
# 5b) and it ALSO applies the derived ones, before root (#19). Without
#     that line the bootstrap creates the substrate's projects, root
#     syncs, and the organizations' Applications end up "project not
#     found".
L_APT="$(grep -n 'appprojects-tenants.yaml' "$PHASES/35-gitops.sh" | head -1 | cut -d: -f1)"
if [[ -z "$L_APT" ]] || (( L_APT > L_ROOT )); then
    D76="$D76 phase 35 does not apply appprojects-tenants.yaml before root (or it is missing);"
fi
# 6) THE INVARIANT THAT WAS MISSING (#19): every project an Application
#    references has to be DEFINED in one of the two files.
#
#    Until 2026-08-05 the tenant AppProjects were written by hand, so
#    registering an organization meant: contract, generator, push... and
#    remembering one more file. Nothing checked it. The symptom arrives
#    late and far away —the app exists, the pipeline builds, and ArgoCD
#    says "project not found" only at deploy time—, and it arrives only
#    if someone is looking. This catches it in a clone, with no cluster.
#
#    The INVARIANT is what is checked (reference ⊆ definition), not a
#    list of names: a list would be the fifth place to remember.
#
#    MIND THE PATH. Until 2026-08-11 this block walked `platform/k8s`
#    —the INSTANCE— while the rest of check 76 was already looking at
#    the seed. It is the same mistake this file's header documents, with
#    the usual aggravation: `platform/` is in .gitignore, so in a clean
#    clone it does not exist, `os.walk` over an absent directory does
#    not iterate, both sets come out empty and "there are no orphans"
#    comes out GREEN for not having looked. That is why below it demands
#    having found at least one Application: a sweep that swept nothing
#    is not a verdict.
python3 - "$AEGIS_ROOT" <<'PY' || D76="$D76 there are Applications referencing an AppProject that nobody defines;"
import os, re, sys
root = os.path.join(sys.argv[1], "seed", "platform", "k8s")
if not os.path.isdir(root):
    print(f"    {root} does not exist: the check cannot have an opinion", file=sys.stderr)
    sys.exit(1)
defined, references = set(), {}
for base, _, files in os.walk(root):
    for a in files:
        if not a.endswith((".yaml", ".yml")):
            continue
        path = os.path.join(base, a)
        try:
            txt = open(path, encoding="utf-8").read()
        except OSError:
            continue
        # It is read with a regex and not with yaml.safe_load on
        # purpose: a good part of these files are kustomize/helm
        # templates that do not parse as plain YAML. The invariant does
        # not need the tree, it needs the two sets.
        if "kind: AppProject" in txt:
            defined |= set(re.findall(r"^\s+name:\s*(\S+)", txt, re.M))
        if "kind: Application" in txt:
            for p in re.findall(r"^\s*project:\s*(\S+)", txt, re.M):
                references.setdefault(p, set()).add(os.path.relpath(path, root))
if not references:
    print("    zero Applications found: the invariant was not evaluated", file=sys.stderr)
    sys.exit(1)
orphans = {p: v for p, v in references.items() if p not in defined}
if orphans:
    for p, where in sorted(orphans.items()):
        print(f"    project '{p}' referenced by {sorted(where)} and defined NOWHERE",
              file=sys.stderr)
    sys.exit(1)
PY
if [[ -n "$D76" ]]; then fail "appprojects:$D76"
else pass "Apps in defined AppProjects; tenant denies cluster-scoped; projects (fixed and derived) before root"; fi
}
