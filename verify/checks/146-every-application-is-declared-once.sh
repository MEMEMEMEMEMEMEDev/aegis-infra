# title: every ArgoCD Application in the seed is declared exactly once
# origin: new in v3 — 2026-08-27, root OutOfSync: "hello-aegis is part of applications argocd/root and org-canary"
check() {
# Two files declaring the same Application are two owners of one live
# object: whichever syncs last wins, the other reports OutOfSync, and
# the two copies drift apart the first time somebody edits one — which
# is what happened the day the canary's ignoreDifferences was removed
# from its tenant bundle while a second copy under argocd-apps/ kept
# it. One object, one owner, and this check counts.
D146=""
DUP="$(cd "$SEED/platform/k8s" && python3 - <<'PY'
import glob, yaml, collections
seen = collections.defaultdict(list)
for f in sorted(glob.glob("**/*.yaml", recursive=True)):
    try: docs = list(yaml.safe_load_all(open(f)))
    except Exception: continue
    for d in docs:
        if isinstance(d, dict) and d.get("kind") == "Application" and str(d.get("apiVersion","")).startswith("argoproj.io/"):
            seen[(d.get("metadata",{}).get("namespace","argocd"), d["metadata"]["name"])].append(f)
for (ns, n), fs in sorted(seen.items()):
    if len(fs) > 1: print(f"{ns}/{n}: {', '.join(fs)}")
print(f"#{len(seen)}")
PY
)"
N146="$(echo "$DUP" | grep -o '^#[0-9]*' | tr -d '#')"
D146="$(echo "$DUP" | grep -v '^#' | sed 's/^/ /' | tr '\n' ';')"
printf '    %s Applications declared under seed/platform/k8s\n' "${N146:-?}"
if [[ -n "$D146" ]]; then fail "an Application with two owners:$D146"
else pass "every Application is declared once (one live object, one owner)"; fi
}
