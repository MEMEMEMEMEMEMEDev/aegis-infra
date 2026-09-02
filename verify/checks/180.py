# scanner of check 180 — the README's list of gaps does not deny what
# the artifact ships.
#
# Every claim below is answered by a fact DERIVED from the tree, never
# by a list of truths kept here: a check with its own roster of what
# the product can do is one more place to go stale, which is precisely
# the defect being hunted.
#
# What this does NOT measure, said out loud because the honest shape of
# this check is a narrow one: a gap claim added tomorrow is not covered
# until somebody derives its fact. This guards the four that actually
# decayed, and the class they belong to.
import pathlib
import re
import sys

raiz = pathlib.Path(sys.argv[1])


def sin_comentarios(p):
    try:
        return "\n".join(l for l in p.read_text(encoding="utf-8", errors="replace").splitlines()
                         if not re.match(r"^\s*#", l))
    except OSError:
        return ""


readme = raiz / "README.md"
if not readme.is_file():
    print("there is no README.md: this check has no subject")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(2)

texto = readme.read_text(encoding="utf-8", errors="replace")
m = re.search(r"^## Lo que no está\s*$(.*?)^## ", texto, re.M | re.S)
if not m:
    print("README.md no longer has a «Lo que no está» section: the artifact stopped declaring "
          "its own gaps, and a product that lists no gaps is not a more finished product")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(0)
seccion = m.group(1)

datos = sin_comentarios(raiz / "libexec" / "aegis-data")
secreto = sin_comentarios(raiz / "libexec" / "aegis-secret")
plantillas = sorted(p.name for p in (raiz / "seed" / "templates").glob("*") if p.is_dir())

# (fact that holds, claim that then becomes false, why it costs)
casos = [
    (len(plantillas) > 1,
     re.compile(r"[Uu]na sola plantilla|only one template", re.I),
     f"the seed ships {len(plantillas)} templates ({', '.join(plantillas)}) and the README "
     f"still says there is a single one"),

    (bool(re.search(r"def restore_bucket\b", datos)) and bool(re.search(r's3\("PUT"', datos)),
     re.compile(r"no los objetos del bucket|not the bucket objects", re.I),
     "aegis-data restores bucket objects (restore_bucket puts them back over S3) and the "
     "README still says restore leaves them behind, which sends the operator to re-upload "
     "by hand what the product already returned"),

    ("ALTER ROLE" in datos,
     re.compile(r"se realinea a\s+mano|realign(ed)? by hand", re.I),
     "aegis-data issues the ALTER ROLE itself and the README still asks the operator to type "
     "it, at the one moment they are already restoring under pressure"),

    (secreto.count("copy_source_for") >= 1,
     re.compile(r"`aegis secret create` no deriva|secret create does not derive", re.I),
     "aegis-secret derives the copied registry credential and the README still says it does "
     "not, pointing at a command that needs the private age key for work that no longer "
     "needs it"),
]

malo = []
for vale, patron, porque in casos:
    if vale and patron.search(seccion):
        malo.append(porque)

for l in malo:
    print(l)
print(f"__COUNT__ {len(casos)} {len(plantillas)}", file=sys.stderr)
