# title: every alert the documents cite exists in the rules
# origin: new in v3 — 2026-08-27, when the images protocol started naming six alerts
check() {
# Sibling of check 106. That one keeps the documents honest about
# COMMANDS; this one about ALERTS. A protocol says «when alert
# `UpstreamFixAvailable` fires, re-mirror» — and the operator waits for
# an alert that was renamed, or never written, while the image serves
# with a fixable CVE. A document that names an alert that does not exist
# ages exactly like code and nothing turns red.
#
# SCOPE: the documents that are shipped and read — docs/ of the product
# and docs/ of the seed. The citation is the word `alert` followed by a
# backticked Name (`alert \`Foo\``), which is the house form; prose that
# says «an alert» without a backtick is not a citation, and neither is a
# backticked word that is not preceded by `alert` (a `kind
# \`ClusterPolicy\`` is a kind). plan/ is the record and verify/teeth
# are the mutations: both are out, the same reason as in 106.
#
# Zero citations is red, not green: the images protocol cites six, and
# an instrument that finds none is reading the wrong shelf.
D140=""
ROOT="$AEGIS_ROOT" python3 - <<'PY' || D140=" (see the detail above);"
import os, pathlib, re, sys, yaml
root = pathlib.Path(os.environ["ROOT"])
rules = root / "seed/platform/k8s/base/observability/rules/vmalert-rules.yaml"
if not rules.is_file():
    print(f"    {rules.relative_to(root)} does not exist: there are no alerts for the documents to cite", file=sys.stderr); sys.exit(1)
cm = yaml.safe_load(rules.read_text())
declared = {r["alert"] for body in cm["data"].values()
            for g in yaml.safe_load(body)["groups"] for r in g.get("rules", []) if "alert" in r}
OUT = ("plan/", "verify/teeth")
docs = [p for base in ("docs", "seed/platform/docs") for p in (root / base).rglob("*.md")
        if not any(o in str(p.relative_to(root)) for o in OUT)]
CITE = re.compile(r"\balert\s+`([A-Za-z][A-Za-z0-9_]*)`")
bad, n = [], 0
for d in sorted(docs):
    for name in CITE.findall(d.read_text(errors="replace")):
        n += 1
        if name not in declared:
            bad.append(f"{d.relative_to(root)}: cites alert `{name}` and no rule declares it")
print(f"    {n} alert citations in {len(docs)} documents, {len(declared)} alerts declared", file=sys.stderr)
if n == 0:
    bad.append("no document cites any alert: nothing measured (the images protocol cites six — is it there, and in the house form `alert `Name``?)")
for b in sorted(set(bad)): print(f"    {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D140" ]]; then fail "documents citing alerts:$D140"
else pass "every alert the documents cite is declared in vmalert-rules.yaml"; fi
}
