"""Check 225 — a seed change reaches a living instance without taking what is hers.

Driven, not read: a scratch «seed» and a scratch «instance» are built
with every case the classification has to tell apart, and the two verbs'
machinery (lib/aegis/seed.py, which libexec/aegis-seed is a thin shell
over) is run over them.
"""
import os
import re
import sys
import tempfile
import pathlib

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []
driven = 0

CMD = os.path.join(ROOT, "libexec", "aegis-seed")
if not os.path.isfile(CMD):
    print("SCOPE: no aegis seed")
    sys.exit(0)
try:
    from aegis import seed, markers, pins
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/seed.py cannot be imported: {e}")
    print("SCOPE: nothing driven")
    sys.exit(0)

cmd = open(CMD, encoding="utf-8").read()
code = "\n".join(l for l in cmd.splitlines() if not l.lstrip().startswith("#"))

# ── 1. the command copies THROUGH the render, never bare ────────────
if "seed_fetch" not in code:
    findings.append("aegis seed apply does not go through seed_fetch: a bare copy puts the seed's "
                    "placeholders back into a rendered tree (measured 2026-09-01)")
# a cp of the seed INTO the instance is the sin; a cp into a scratch tree
# that is then rendered for the comparison is how diff works
if re.search(r"^\s*cp\s+.*seed/platform.*\$PLATFORM_DIR", code, re.M):
    findings.append("aegis seed copies a seed file into the instance with a bare cp")
for verb in ("snapshot", "repin", "block-snapshot", "block-splice", "owns", "classify"):
    if f"aegis.seed {verb}" not in code:
        findings.append(f"aegis seed never calls `aegis.seed {verb}`: "
                        + {"snapshot": "the instance's pins are not read before the copy",
                           "repin": "the instance's pins are not written back after the copy",
                           "block-snapshot": "the derived blocks are not kept before the copy",
                           "block-splice": "the derived blocks are not put back after the copy",
                           "owns": "apply does not refuse what the instance owns",
                           "classify": "diff does not classify"}[verb])
if not re.search(r"\[DRY-RUN\]", code):
    findings.append("aegis seed apply has no dry run: it acts on the first call")
if "git -C \"$PLATFORM_DIR\" push" in code or re.search(r"git\s+push", code):
    findings.append("aegis seed apply pushes: the commit is the operator's to read and push")

# ── 2. ownership: what org.py writes wholesale is the instance's ────
org = open(os.path.join(ROOT, "lib", "aegis", "org.py"), encoding="utf-8").read()
for const, rel in (("AI_REGISTRY", "k8s/base/ai-system/registro.yaml"),
                   ("ROUTES_K8S", "k8s/base/ai-system/routes.yaml"),
                   ("TENANTS_K8S", "k8s/argocd-apps/tenants.yaml"),
                   ("APPPROJECTS_K8S", "k8s/bootstrap/appprojects-tenants.yaml"),
                   ("PROVISION_K8S", "k8s/base/garage-system/aprovisionar.yaml"),
                   ("MAIN_TF", "tofu/envs/cloudflare-tunnel/main.tf")):
    if const in org and not seed.instance_owns(rel):
        findings.append(f"{rel} is written wholesale by aegis org apply ({const}) and aegis seed "
                        f"would bring the seed's sample over it")
for rel in ("orgs/drop.yaml", "plans.yaml", "services.yaml", "mirror-images/images.txt",
            "k8s/organizations/org-x/bundle.yaml", "tofu/envs/data-r2/main.tf",
            "k8s/base/x/secret-y.enc.yaml"):
    if not seed.instance_owns(rel):
        findings.append(f"{rel} is not recognised as the instance's")
for rel in ("k8s/base/observability/rules/vmalert-rules.yaml", "base-images/Jenkinsfile",
            "ai/routes.yaml", "docs/protocols/templates/Jenkinsfile.app"):
    if seed.instance_owns(rel) or seed.is_mixed(rel):
        findings.append(f"{rel} is the seed's and the classifier would never bring it over")
for rel in seed.DERIVED_BLOCKS:
    if seed.instance_owns(rel):
        findings.append(f"{rel} carries a derived block AND is marked the instance's: its seed "
                        f"structure could never be brought over")

# ── 3. the classification, driven over a scratch pair ───────────────
with tempfile.TemporaryDirectory() as td:
    S = pathlib.Path(td) / "seed"; I = pathlib.Path(td) / "inst"
    def put(root, rel, text):
        p = root / rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
    # same
    put(S, "docs/a.md", "hello\n"); put(I, "docs/a.md", "hello\n")
    # pinned only: the instance moved a chart version and an image tag
    put(S, "k8s/argocd-apps/x.yaml", "kind: Application\nspec:\n  source:\n    chart: c\n    targetRevision: 1.0.0\n")
    put(I, "k8s/argocd-apps/x.yaml", "kind: Application\nspec:\n  source:\n    chart: c\n    targetRevision: 1.2.0\n")
    put(S, "ci-images/Jenkinsfile", "pod:\n  image: gcr.io/kaniko-project/executor:v1.23.2-debug\nstage('x') {}\n")
    put(I, "ci-images/Jenkinsfile", "pod:\n  image: gcr.io/kaniko-project/executor:v1.24.0-debug\nstage('x') {}\n")
    # a real change (structure) beside a moved pin
    put(S, "base-images/Jenkinsfile", "image: a:v1.23.2-debug\nstage('members') { new }\n")
    put(I, "base-images/Jenkinsfile", "image: a:v1.24.0-debug\nstage('members') { old }\n")
    # added by the seed
    put(S, "k8s/base/new.yaml", "kind: Role\n")
    # owned: differs and must not be reported as a change to bring
    put(S, "plans.yaml", "pequena: {}\n"); put(I, "plans.yaml", "pequena: {}\ndeposito: {}\n")
    # mixed: the phases append
    put(S, "k8s/base/garage-system/kustomization.yaml", "resources:\n  - a.yaml\n")
    put(I, "k8s/base/garage-system/kustomization.yaml", "resources:\n  - a.yaml\n  - secret-x.enc.yaml\n")
    # generated material: a PEM in the instance, a marker in the seed
    put(S, "k8s/base/observability/configmap-aegis-ca.yaml", "data:\n  ca.crt: |\n    __OBS_CA_PEM__\n")
    put(I, "k8s/base/observability/configmap-aegis-ca.yaml", "data:\n  ca.crt: |\n    -----BEGIN CERTIFICATE-----\n    MIIB\n    -----END CERTIFICATE-----\n")
    # a derived block: same structure, different block
    j = "k8s/base/platform/jenkins/values.yaml"
    blk_s = markers.JOBS_BLOCK_START + "\n" + markers.JOBS_BLOCK_END
    blk_i = markers.JOBS_BLOCK_START + "\n          - script: >\n              multibranchPipelineJob('shop-web-mb') {}\n" + markers.JOBS_BLOCK_END
    put(S, j, "controller:\n  x: 1\n" + blk_s + "\n")
    put(I, j, "controller:\n  x: 1\n" + blk_i + "\n")
    c = seed.classify(S, I); driven += 1
    want = {"same": 3, "owned": ["plans.yaml"], "mixed": ["k8s/base/garage-system/kustomization.yaml"],
            "pinned": ["ci-images/Jenkinsfile", "k8s/argocd-apps/x.yaml"],
            "added": ["k8s/base/new.yaml"], "differs": ["base-images/Jenkinsfile"]}
    for k, v in want.items():
        got = c.get(k)
        if (sorted(got) if isinstance(got, list) else got) != v:
            findings.append(f"classify: {k} = {got!r}, expected {v!r}")

    # ── 4. apply keeps the instance's derived block and pins ────────
    # the derived block
    before = (I / j).read_text()
    put(I, j, (S / j).read_text())                       # the «copy»
    driven += 1
    if not seed.splice_block(I, j, before) or "shop-web-mb" not in (I / j).read_text():
        findings.append("after a copy the instance's derived block (its tenant jobs) is not put back")
    # the pins: a chart the instance had at 1.2.0, the seed at 1.0.0
    ins = I / "k8s/argocd-apps"; (ins / "core.yaml").write_text(
        "apiVersion: argoproj.io/v1alpha1\nkind: Application\nmetadata:\n  name: argocd\nspec:\n  sources:\n    - repoURL: https://example/charts\n      chart: argo-cd\n      targetRevision: 1.2.0\n")
    before_pins = pins.read(str(I))
    (ins / "core.yaml").write_text((ins / "core.yaml").read_text().replace("1.2.0", "1.0.0"))
    restored, gone = seed.repin(I, before_pins, ["k8s/argocd-apps/core.yaml"]); driven += 1
    if "targetRevision: 1.2.0" not in (ins / "core.yaml").read_text():
        findings.append(f"after a copy the instance's pin (a chart at 1.2.0) is not written back: "
                        f"restored={restored!r} gone={gone!r} — a seed apply would be a downgrade")

for f in findings:
    print(f)
print(f"SCOPE: the command read for its render, its dry run and its no-push; ownership checked against "
      f"what org.py writes; {driven} classification/splice/repin run(s) driven over scratch trees")
