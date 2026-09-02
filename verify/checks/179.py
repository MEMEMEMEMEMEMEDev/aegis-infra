# scanner of check 179 — no runtime message tells the operator that a
# verb this product dispatches does not exist.
#
# It reads only what the operator can actually be SHOWN: non-comment
# lines of the phases, the commands and the libraries. Comments are
# dropped first, and not as a formality — this file and the check that
# calls it explain the defect using the very words the defect is made
# of, so a scan that read prose would accuse its own explanation. That
# error was made eight times in one day in this repository; the tooth
# of this check keeps a control that is exactly such a paragraph.
#
# The truth about what exists is DERIVED, never listed: a verb exists
# if libexec/aegis-<verb> is there, and a subcommand exists if that
# file's own `# aegis-subcommands:` header names it — the same source
# bin/aegis reads to dispatch and check 112 reads to validate calls.
import pathlib
import re
import sys

raiz = pathlib.Path(sys.argv[1])
libexec = raiz / "libexec"

# ── what the product really dispatches ────────────────────────────
verbos = {}
for f in sorted(libexec.glob("aegis-*")):
    nombre = f.name[len("aegis-"):]
    subs = set()
    try:
        cabeza = f.read_text(encoding="utf-8", errors="replace").splitlines()[:20]
    except OSError:
        continue
    for l in cabeza:
        m = re.match(r"^#\s*aegis-subcommands:\s*(.+)$", l)
        if m:
            subs = set(m.group(1).split())
            break
    verbos[nombre] = subs

if not verbos:
    print("no command could be derived from libexec/: this check has no idea what exists, "
          "so it cannot tell a true statement from a stale one")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(2)

# The ways a message can say «that is not here». Deliberately narrow:
# a claim about ABSENCE, not a refusal, a warning or a precondition.
NIEGA = re.compile(
    r"does not exist|doesn'?t exist|does not yet exist|no existe|todav[ií]a no existe|"
    r"is not implemented|no est[aá] implementado|is not a command|no es un comando",
    re.I)
CITA = re.compile(r"`?\baegis\s+([a-z][a-z0-9-]*)(?:\s+([a-z][a-z0-9-]*))?")

objetivo = []
for patron in ("init/*.sh", "init/phases/*.sh", "libexec/*", "lib/*.sh"):
    objetivo += sorted(raiz.glob(patron))

malo = []
n_lineas = 0
for f in objetivo:
    if f.is_dir():
        continue
    try:
        texto = f.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    for n, l in enumerate(texto.splitlines(), 1):
        if re.match(r"^\s*#", l):        # prose is not a runtime message
            continue
        n_lineas += 1
        if not NIEGA.search(l):
            continue
        for verbo, sub in CITA.findall(l):
            if verbo not in verbos:
                continue
            if sub and sub not in verbos[verbo]:
                continue
            que = f"aegis {verbo} {sub}".strip()
            malo.append(
                f"{f.relative_to(raiz)}:{n} tells the operator that `{que}` does not exist, and "
                f"it does: {'the subcommand is declared by' if sub else 'it is'} "
                f"libexec/aegis-{verbo}. The message is read at the exact moment the operator "
                f"needs that verb, and it sends them away from it")

for l in malo:
    print(l)
print(f"__COUNT__ {len(verbos)} {n_lineas}", file=sys.stderr)
