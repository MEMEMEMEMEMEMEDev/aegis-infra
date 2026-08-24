# title: temporal coupling: generator entries vs sync phase
# origin: verify-static.sh (v2) ══ 18
check() {
# Run #4 (the bug that stopped it): a static entry whose .enc.yaml is
# generated in a phase LATER than the first sync of its App breaks
# kustomize's atomic build → NO secret of the App is created.
# Invariant: producing-phase(entry) ≤ phase-of-the-first-argo_sync(App).
# (automated Apps with no explicit sync count as phase 35 — the root
# creates them and the automated policy syncs them right there.)
# REWRITTEN on 2026-08-05 (#48). The check had two defects that made it
# shout about the healthy and keep quiet about the broken:
#
#   1. IT INDEXED BY FILE NAME. There are seven
#      `secret-regcred-internal.enc.yaml` in different directories, and
#      all of them inherited the phase of the only one an init phase
#      produces (the one of org-canary). Six FAILs over files that have
#      nothing to do with it. Worse: it counted the SED PATTERNS as a
#      "producer" —`sed '/file.enc.yaml/a\ ...'` is an address, not
#      a write— so it attributed production to somebody who only reads.
#
#   2. IT TOOK THE EXPLICIT `argo_sync` as the first sync. An App with
#      `automated` is synced by ArgoCD as soon as root creates it, in
#      phase 35, whether or not there is an argo_sync afterwards. That
#      UNDERESTIMATES the window.
#
# And the invariant was refined into two levels, because not everything
# late hurts the same:
#
#   FATAL      the entry is produced AFTER an explicit `argo_sync` of
#              its App. That sync is a GATE: the phase dies there. On a
#              start with a NEW age key the file is in git but
#              encrypted with a key that no longer exists, KSOPS does
#              not decrypt it, and the build fails just as if it were
#              missing.
#   window     it is produced after the AUTOMATIC sync but before any
#              gate. The App stays OutOfSync for a while and `selfHeal`
#              recovers it when the producing phase rewrites the file.
#              It is reported, not failed: a permanent red switches the
#              signal off just as a false green does.
if python3 - "$AEGIS_ROOT" <<'EOF'
import re, sys, yaml, pathlib
root = pathlib.Path(sys.argv[1]); P = root/"seed"/"platform"
# App: path -> name, and whether it is automated (it syncs on its own
# in phase 35):
apps, automated = {}, {}
for f in (P/"k8s"/"argocd-apps").glob("*.yaml"):
    for d in yaml.safe_load_all(f.open()):
        if not d or d.get("kind") != "Application": continue
        name = d["metadata"]["name"]
        automated[name] = "automated" in (d["spec"].get("syncPolicy") or {})
        for s in (d["spec"].get("sources") or [d["spec"].get("source")]):
            if s and "path" in s:
                apps[s["path"]] = name
gate_sync = {}   # the EXPLICIT argo_sync: it is where the phase plants itself
for ph in (root/"init"/"phases").glob("[0-9][0-9]-*.sh"):
    n = int(ph.name[:2])
    for m in re.finditer(r'argo_sync\s+([a-z0-9-]+)', ph.read_text()):
        a = m.group(1)
        gate_sync[a] = min(gate_sync.get(a, 99), n)

# producing phase by PATH, not by name. The phases name destinations
# with variables; the two that are used get expanded and everything
# that does not end up being a real path under k8s/ is discarded (that
# leaves out the sed patterns, which start with '/').
def _rel(s):
    for v in ("$PLATFORM_DIR/", "${PLATFORM_DIR}/"): s = s.replace(v, "")
    for v in ("$B/", "${B}/"): s = s.replace(v, "k8s/base/")
    return s
producer = {}
for ph in (root/"init"/"phases").glob("[0-9][0-9]-*.sh"):
    n = int(ph.name[:2])
    for m in re.finditer(r'([A-Za-z0-9_.${}/-]+\.enc\.yaml)', ph.read_text()):
        r = _rel(m.group(1))
        if r.startswith("k8s/"):
            producer[r] = min(producer.get(r, 99), n)

ok = True; checked = 0; windows = []
for g in sorted(P.rglob("secret-generator.yaml")):
    gdir = str(g.parent.relative_to(P))
    app = apps.get(gdir)
    if app is None:
        print(f"FAIL generator with no App including it: {gdir}"); ok = False
        continue
    gate = gate_sync.get(app, 99)
    auto = 35 if automated.get(app) else 99
    for e in (yaml.safe_load(g.open()) or {}).get("files", []):
        checked += 1
        # The file is NOT required to exist nor to be versioned, and
        # that is deliberate: IN THE SEED NONE OF THEM EXISTS. The init
        # creates them, and commits them afterwards. Demanding it gave
        # 12 FAILs against a virgin clone — that is, against the very
        # artifact this verifier exists to verify. What matters is the
        # ORDER.
        rel = f"{gdir}/{e}"
        prod = producer.get(rel)
        if prod is None:
            continue   # the contract path produces it; check 4 covers it
        if prod > gate:
            print(f"FAIL temporal coupling: {rel} is produced in phase {prod} "
                  f"but phase {gate} PLANTS ITSELF on `argo_sync {app}` — with a "
                  f"new age key that file does not decrypt and the phase dies there")
            ok = False
        elif prod > auto:
            windows.append(f"{rel} (phase {prod} > automatic sync 35, App {app})")
print(f"entries verified against sync phases: {checked}")
if windows:
    print(f"  windows recoverable by selfHeal ({len(windows)}):")
    for v in windows:
        print(f"    - {v}")
# 18b — CRD variant of the same class (post-#4 review): a CR whose CRD
# is installed by a chart from a LATER phase cannot be static in a
# kustomization that syncs earlier. The CR must (1) NOT be in any
# static kustomization and (2) be added by the phase that installs its
# CRD, in the same commit.
#
# THERE IS NO CASE TODAY: the only one was the Image Updater's CR and
# it was withdrawn in #59. The guard is kept on purpose —the trap comes
# back with the next chart that brings its own CRD— and that is why it
# prints HOW MANY it verified: "0 verified" and "all fine" do not look
# the same.
CR_APIS = ("argocd-image-updater.argoproj.io",)
crs = [f for f in P.rglob("*.yaml")
       if f.name != "kustomization.yaml"
       and any(a in f.read_text() for a in CR_APIS)]
f70 = (root/"init"/"phases"/"70-deploy-auto.sh").read_text()
for cr in crs:
    k = cr.parent/"kustomization.yaml"
    # parse the YAML, do not grep: the filename legitimately appears in
    # the COMMENT that documents this very rule:
    kres = (yaml.safe_load(k.open()) or {}).get("resources", []) \
           if k.exists() else []
    if cr.name in kres:
        print(f"FAIL CR with a phase-70 CRD listed STATICALLY: "
              f"{cr.relative_to(P)} (it would break the earlier sync)"); ok = False
    if cr.name not in f70 or "kustomization.yaml" not in f70:
        print(f"FAIL phase 70 does not add {cr.name} to the kustomization "
              f"(the CR would be orphaned — never applied)"); ok = False
print(f"late-CRD CRs verified: {len(crs)}")
sys.exit(0 if ok else 1)
EOF
then pass "no entries from phases later than their App's sync (+late-CRD CRs)"
else fail "temporal coupling in generators"; fi
}
