"""Scanner of check 187 — an ignore that could hide a value is conditional.

Prose is stripped BEFORE scanning: the comments around these blocks name
`/metadata/annotations` and quote the very expressions being asked about.
"""
import os
import re
import sys

ROOT = sys.argv[1]

# Fields of metadata that CARRY INFORMATION. Ignoring one of these
# outright blinds the comparison to a real change; the artifact only
# ever needs the empty case, which is a chart's rendering bug.
CON_SENTIDO = ("annotations", "labels")


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


RE_BLOQUE = re.compile(r"^(\s*)ignoreDifferences:\s*$", re.M)

fallos = []
hechos = 0
entradas = 0

for f in fuentes():
    with open(f, encoding="utf-8", errors="replace") as fh:
        texto = sin_prosa(fh.read())
    rel = os.path.relpath(f, ROOT)
    for m in RE_BLOQUE.finditer(texto):
        sangria = len(m.group(1))
        cuerpo = []
        for linea in texto[m.end():].splitlines():
            if linea.strip() and (len(linea) - len(linea.lstrip())) <= sangria:
                break
            cuerpo.append(linea)
        entradas += 1
        for linea in cuerpo:
            s = linea.strip()
            # jsonPointers, in either YAML form
            for campo in CON_SENTIDO:
                if "/metadata/%s" % campo in s:
                    fallos.append(
                        "%s ignores /metadata/%s through a jsonPointer, which "
                        "cannot be conditional: every annotation and label of "
                        "that kind stops being compared" % (rel, campo)
                    )
            # jq expressions
            if s.startswith("- ") and (".annotations" in s or ".labels" in s):
                expr = s[2:].strip().strip("'\"")
                if "select(" not in expr.replace(" ", "").replace("select (", "select("):
                    fallos.append(
                        "%s ignores `%s` with no condition: it has to match only "
                        "when the map is empty, or a real value is hidden too"
                        % (rel, expr)
                    )
                elif "length" not in expr and "== {}" not in expr:
                    fallos.append(
                        "%s conditions `%s` on something other than the map "
                        "being empty" % (rel, expr)
                    )

hechos = 2  # the jsonPointer form and the jq form

for f in fallos:
    print(f)
print("__COUNT__ %d over %d ignoreDifferences block(s)" % (hechos, entradas), file=sys.stderr)
