"""Check 271 — the alerts climb the books' ladder.

Until plan/21 one alert, ImageWithFixableVulns, turned every finding the
watch saw into the same warning a day later. Once the door lets findings
in as debt with a window, that alert would page twice a day, for weeks,
about debt the platform accepted on purpose — and an alert that never
stops is an alert nobody reads.

The ladder (plan/21 §4.4), over ledger.sh's aegis_vuln_findings{state}:
  VulnDebt info · VulnDebtDueSoon warning · VulnDebtOverdue critical ·
  VulnExploited critical, with no `for`.
This sidecar reads the rules and alertmanager's routes and asserts each
rung reads the state ledger.sh actually emits (the states are read from
ledger.sh's --metrics, not retyped here), carries its severity, tells
the reader the command (`aegis vulns`), and that the three debt rungs
repeat once a day while the exploited one keeps the default cadence.
"""
import os
import re
import sys

import yaml

ROOT = os.path.abspath(sys.argv[1])
OBS = os.path.join(ROOT, "seed", "platform", "k8s", "base", "observability")
LEDGER = os.path.join(ROOT, "seed", "platform", "image-watch", "ledger.sh")
findings = []

rules_doc = yaml.safe_load(open(os.path.join(OBS, "rules", "vmalert-rules.yaml"), encoding="utf-8"))
rules = {}
for key, text in (rules_doc.get("data") or {}).items():
    for g in (yaml.safe_load(text) or {}).get("groups") or []:
        for r in g.get("rules") or []:
            if "alert" in r:
                rules[r["alert"]] = r

m = re.search(r'split\("([a-z_ ]+)", st, " "\)', open(LEDGER, encoding="utf-8").read())
emitted = set(m.group(1).split()) if m else set()
if not emitted:
    findings.append("ledger.sh --metrics no longer says which states it emits: re-aim this check")

LADDER = {"VulnDebt": ("debt", "info"), "VulnDebtDueSoon": ("due_soon", "warning"),
          "VulnDebtOverdue": ("overdue", "critical"), "VulnExploited": ("exploited", "critical")}
for name, (state, sev) in LADDER.items():
    r = rules.get(name)
    if not r:
        findings.append(f"the rung {name} is missing")
        continue
    expr = " ".join(str(r.get("expr", "")).split())
    if f'aegis_vuln_findings{{state="{state}"}}' not in expr:
        findings.append(f"{name} does not read aegis_vuln_findings{{state=\"{state}\"}}")
    if state not in emitted:
        findings.append(f"{name} reads state {state!r}, which ledger.sh does not emit: it would never fire")
    if (r.get("labels") or {}).get("severity") != sev:
        findings.append(f"{name} is {(r.get('labels') or {}).get('severity')!r}, not {sev}")
    if "aegis vulns" not in str((r.get("annotations") or {}).get("description", "")):
        findings.append(f"{name} does not tell the reader the command that says what and who fixes it")
if rules.get("VulnExploited", {}).get("for"):
    findings.append("VulnExploited waits (`for:`): an exploited vulnerability is said now")
if "ImageWithFixableVulns" in rules:
    findings.append("ImageWithFixableVulns is still there: every finding is one warning again, the ladder's debt included")

am = next(d for d in yaml.safe_load_all(open(os.path.join(OBS, "alertmanager.yaml"), encoding="utf-8"))
          if isinstance(d, dict) and d.get("kind") == "ConfigMap")
conf = yaml.safe_load(am["data"]["alertmanager.yml"].replace("__OBS_DEADMAN_REPEAT__", "24h"))
daily = None
for rt in (conf.get("route") or {}).get("routes") or []:
    ms = " ".join(rt.get("matchers") or [])
    if "VulnDebt" in ms:
        daily = rt
if not daily:
    findings.append("alertmanager has no route for the debt rungs: debt pages every 12h like an outage")
else:
    ms = " ".join(daily.get("matchers") or [])
    pat = re.search(r'alertname=~"([^"]+)"', ms)
    names = set(pat.group(1).split("|")) if pat else set()
    if names != {"VulnDebt", "VulnDebtDueSoon", "VulnDebtOverdue"}:
        findings.append(f"the daily route matches {sorted(names)}, not the three debt rungs (and never VulnExploited)")
    if daily.get("repeat_interval") != "24h":
        findings.append(f"the debt rungs repeat every {daily.get('repeat_interval')}, not once a day")

for x in findings:
    print(x)
print(f"SCOPE: {len(rules)} alert(s) read; the 4 rungs against the {len(emitted)} state(s) ledger.sh emits; alertmanager's routes")
