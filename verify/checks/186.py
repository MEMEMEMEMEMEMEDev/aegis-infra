"""Scanner of check 186 — Kyverno's defaults, ignored wherever a policy ships.

Prose is stripped BEFORE scanning: the comments around these blocks name
`ClusterPolicy`, `Policy` and the very expressions being asked about, and
a scanner that reads them would measure its own documentation.
"""
import os
import re
import sys

ROOT = sys.argv[1]
KYVERNO_KINDS = ("ClusterPolicy", "Policy")

# The one default MEASURED to break it (2026-09-04, org-portafolio held
# OutOfSync for two days). Named here because a list that lost it would
# reopen the hole while still being self-consistent.
MEASURED = "skipBackgroundRequests"


def sin_prosa(text):
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def fuentes():
    out = []
    for dirpath, _, names in os.walk(os.path.join(ROOT, "seed/platform/k8s")):
        for n in names:
            if n.endswith((".yaml", ".yml")):
                out.append(os.path.join(dirpath, n))
    gen = os.path.join(ROOT, "lib/aegis/org.py")
    if os.path.exists(gen):
        out.append(gen)
    return sorted(out)


def _expr(linea):
    """One jq expression, freed of what surrounds it.

    In org.py these blocks live inside an f-string, so the last one ends
    with the closing `\"\"\")` of the template. A scanner that did not cut
    there would report a difference between two lists that are equal.
    """
    v = linea.strip().lstrip("-").strip()
    v = v.split('"""')[0]
    return v.strip().strip("'\"")


def _sync_opts(chunk):
    """syncOptions in either YAML form: inline list or block list."""
    m = re.search(r"syncOptions:\s*\[([^\]]*)\]", chunk)
    if m:
        return m.group(1)
    m = re.search(r"syncOptions:\s*\n((?:\s*-\s+\S.*\n)+)", chunk)
    return m.group(1) if m else ""


RE_KIND = re.compile(r"apiVersion:\s*kyverno\.io/\S+\s*\n\s*kind:\s*(\w+)")
RE_ENTRY = re.compile(
    r"-\s*group:\s*kyverno\.io\s*\n\s*kind:\s*(\w+)\s*\n"
    r"\s*jqPathExpressions:\s*\n((?:\s*-\s+\S.*\n)+)"
)

embarcadas = set()      # kyverno policy kinds the artifact ships or generates
entradas = []           # (file, kind, frozenset(expressions))
apps = []               # (file, kind, chunk) — the App that carries the entry

for f in fuentes():
    with open(f, encoding="utf-8", errors="replace") as fh:
        texto = sin_prosa(fh.read())
    rel = os.path.relpath(f, ROOT)
    for m in RE_KIND.finditer(texto):
        if m.group(1) in KYVERNO_KINDS:
            embarcadas.add(m.group(1))
    for chunk in re.split(r"^---\s*$", texto, flags=re.M):
        if "kind: Application" not in chunk:
            continue
        for m in RE_ENTRY.finditer(chunk):
            exprs = frozenset(x for x in (_expr(l) for l in m.group(2).splitlines()) if x)
            entradas.append((rel, m.group(1), exprs))
            apps.append((rel, m.group(1), chunk))

fallos = []
hechos = 0

# 1 — every kyverno policy kind the artifact ships has an entry.
hechos += 1
cubiertas = {k for _, k, _ in entradas}
for k in sorted(embarcadas - cubiertas):
    fallos.append(
        "the artifact ships kyverno.io/%s and no Application ignores "
        "Kyverno's defaults for that kind" % k
    )

# 2 — the ignore reaches the apply, not only the diff.
hechos += 1
for rel, kind, chunk in apps:
    if "RespectIgnoreDifferences=true" not in _sync_opts(chunk):
        fallos.append(
            "%s ignores Kyverno's defaults on %s but its syncOptions lack "
            "RespectIgnoreDifferences=true, so ArgoCD keeps sending the very "
            "fields it says it ignores" % (rel, kind)
        )

# 3 — one lesson, one list.
hechos += 1
juegos = {e for _, _, e in entradas}
if len(juegos) > 1:
    base = max(juegos, key=len)
    for rel, kind, e in entradas:
        if e != base:
            falta = ", ".join(sorted(base - e)) or "nothing"
            sobra = ", ".join(sorted(e - base)) or "nothing"
            fallos.append(
                "%s (%s) declares a different list from the widest one in the "
                "artifact: missing [%s], extra [%s]" % (rel, kind, falta, sobra)
            )

# 4 — the list still covers the default measured to break it.
hechos += 1
for rel, kind, e in entradas:
    if not any(MEASURED in x for x in e):
        fallos.append(
            "%s (%s) no longer covers %s, the default measured on 2026-09-04 "
            "to hold an organization OutOfSync while everything was Healthy"
            % (rel, kind, MEASURED)
        )

# 5 — a list that ignores everything measures nothing.
hechos += 1
for rel, kind, e in entradas:
    if any(x.strip() in (".spec", ".spec.rules", ".spec.rules[]", ".") for x in e):
        fallos.append(
            "%s (%s) ignores a whole subtree (%s): a real change to the "
            "policy would stop being seen" % (rel, kind, sorted(e)[0])
        )

for f in fallos:
    print(f)
print("__COUNT__ %d" % hechos, file=sys.stderr)
