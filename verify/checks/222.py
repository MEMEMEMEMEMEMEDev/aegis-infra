"""Check 222 — a bump that only reached git is not a bump.

MEASURED 2026-09-20, and it is the quietest failure this protocol has
produced so far. Layer 4 raised six charts: argocd 9.5.20 → 9.7.1,
kyverno 3.8.1 → 3.9.1, jenkins 5.9.29 → 5.9.63, trivy-server
0.24.0 → 0.26.0, vector 0.57.0 → 0.58.0, vmsingle 0.45.0 → 0.46.0. Each
one rendered, was committed, pushed and synced; each app came back
Synced and Healthy; the acceptance found no new failures; the window
closed rc 0 and the layer was recorded as raised. Afterwards every one
of the six was still running its old version.

WHY. A chart's `targetRevision` is not part of what the app deploys. It
is written in the Application OBJECT, under `k8s/argocd-apps`, and that
directory is the source of the App-of-Apps — which carries no
`automated` policy, deliberately: nothing creates or retargets an
Application on this platform without a person. `aegis sync <app>` asks
the app to reconcile its CONTENTS, which it does, perfectly, against
the version its object still names. Nothing is wrong at any point. The
green is real and it is about the wrong thing.

Two separate mistakes, so two separate demands here:

  1. THE FILE'S APPLIER GOES FIRST. Whoever applies the file that was
     edited has to be synced before the app that consumes it. Derived
     from the live Applications and never hardcoded to «root»: the name
     of an App-of-Apps is an instance's choice.
  2. THE VERSION IS ASKED OF THE CLUSTER. «Synced+Healthy» answers a
     question about contents. The version is not in the contents, so if
     the layer does not read it back off the live object it has not
     read it at all.

The routing is DRIVEN here against a kubectl that says what this check
wants; the order and the read-back are facts about control flow and are
read out of the source.
"""
import ast
import os
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
os.environ["AEGIS_ROOT"] = ROOT
findings = []
driven = 0

UPD = os.path.join(ROOT, "libexec", "aegis-update")
if not os.path.isfile(UPD):
    print("SCOPE: there is no aegis update")
    sys.exit(0)
src = open(UPD, encoding="utf-8").read()

from aegis import window as win                                    # noqa: E402

# ── 1. the routing, driven ───────────────────────────────────────────
# An App-of-Apps whose source is the directory the Application objects
# live in; one ordinary app; one app whose source is `k8s/base`, which
# must NOT claim `k8s/base-images/...`; and one pure chart source, which
# applies nothing at all.
APPS = {"items": [
    {"metadata": {"name": "root"},
     "spec": {"source": {"path": "k8s/argocd-apps", "repoURL": "git@example:p.git"}}},
    {"metadata": {"name": "cloudflare-tunnel"},
     "spec": {"source": {"path": "k8s/base/ingress/cloudflare-tunnel"}}},
    {"metadata": {"name": "bases"},
     "spec": {"source": {"path": "k8s/base"}}},
    {"metadata": {"name": "jenkins"},
     "spec": {"sources": [{"chart": "jenkins", "targetRevision": "5.9.63",
                           "repoURL": "https://charts.jenkins.io"},
                          {"path": "k8s/base/platform/jenkins", "ref": "values"}]}},
]}

import json                                                        # noqa: E402
real = win._kubectl


def fake(answers):
    """A kubectl that answers by the jsonpath it was handed.

    Matching on substrings of the WHOLE call and not just on the noun,
    because the two shapes of an Application are the point: an app with
    `spec.sources` answers nothing at all to a `spec.source.chart`
    jsonpath —which is exactly what kubectl does— and every chart app
    on this platform has the several-sources shape.
    """
    def _k(*args, timeout=60):
        joined = " ".join(str(a) for a in args)
        for pattern, reply in answers:
            if all(p in joined for p in pattern):
                return reply
        return (1, "", "the exercise did not expect this call")
    return _k


try:
    win._kubectl = fake([(("applications", "json"), (0, json.dumps(APPS), ""))])

    got = win.appliers_of(["k8s/argocd-apps/core.yaml"])
    driven += 1
    if got != ["root"]:
        findings.append(f"the applier of an Application object is not the App-of-Apps: "
                        f"appliers_of said {got!r}, so a chart bump would be pushed to "
                        f"git and synced on the app that consumes the chart, never on "
                        f"the object that names its version")

    got = win.appliers_of(["k8s/base-images/alpine/Containerfile"])
    driven += 1
    if "bases" in (got or []):
        findings.append("the applier is matched on characters and not on path segments: "
                        "an app whose source is `k8s/base` claims `k8s/base-images/...`, "
                        "and the wrong app gets synced")

    # The decoy app at `k8s/base` genuinely contains this file, so it is
    # a legitimate applier too — nested sources are normal. What must
    # not happen is the values file of a chart app failing to reach the
    # app that carries it.
    got = win.appliers_of(["k8s/base/platform/jenkins/values.yaml"])
    driven += 1
    if "jenkins" not in (got or []):
        findings.append(f"a values file inside a chart app's own source is not routed to "
                        f"that app: appliers_of said {got!r}")

    win._kubectl = fake([])
    got = win.appliers_of(["k8s/argocd-apps/core.yaml"])
    driven += 1
    if got is not None:
        findings.append(f"a kubectl that cannot answer is read as «nobody applies this» "
                        f"({got!r}) instead of «nobody could look»: a bump that cannot "
                        f"be routed would be reported as landed")

    # ── 2. the version read back, driven ─────────────────────────────
    win._kubectl = fake([
        (("spec.sources[*]",), (0, "argo-cd|9.7.1", "")),
        # what kubectl really answers when the app has `sources` and the
        # jsonpath asks for `source`: nothing
        (("spec.source.chart",), (0, "|", "")),
    ])
    driven += 1
    if win.live_chart_version("argocd") != "9.7.1":
        findings.append("the live chart version cannot be read off an Application with "
                        "several sources, which is the shape every chart app here has")

    win._kubectl = fake([])
    driven += 1
    if win.live_chart_version("argocd") is not None:
        findings.append("a kubectl that cannot answer yields a version instead of None: "
                        "the layer would compare the bump against a guess")
finally:
    win._kubectl = real

# ── 3. the order and the read-back, out of the source ────────────────
charts = [n for n in ast.walk(ast.parse(src))
          if isinstance(n, ast.FunctionDef) and n.name == "layer_charts"]
if not charts:
    findings.append("there is no layer_charts to inspect")
else:
    body = ast.get_source_segment(src, charts[0]) or ""
    body = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
    if "appliers_of" not in body:
        findings.append("the chart layer never asks who applies the file it edited: it "
                        "syncs the app that consumes the chart, and the Application "
                        "object keeps naming the old version")
    if "live_chart_version" not in body:
        findings.append("the chart layer never reads the running version back off the "
                        "cluster: «Synced+Healthy» is an answer about contents, and the "
                        "version is not in the contents")
    else:
        i_live = body.index("live_chart_version")
        i_done = body.rindex("done.append")
        if i_live > i_done:
            findings.append("the version is read back after the chart has already been "
                            "counted as raised, which is not a check, it is a note")
    if "appliers_of" in body and "live_chart_version" in body:
        if body.index("appliers_of") > body.index("live_chart_version"):
            findings.append("the applier is synced after the version is read: the read "
                            "would answer about a cluster nobody has told yet")

for f in findings:
    print(f)
print(f"SCOPE: {driven} routing and read-back exercise(s) driven against a kubectl that "
      f"says what this check wants, and the order read out of layer_charts")
