# scanner of check 181 — an environment variable a manifest sets for
# code this same seed ships is a name that code actually reads.
#
# The pairing is DERIVED, never listed: a manifest under
# k8s/base/ai-system/<name>.yaml is matched to the sources under
# ai/<name>/, so a lane added tomorrow is covered without anybody
# editing this file.
#
# Only names the product owns (AEGIS_*) are judged. A third party's
# variable is read inside a library this check cannot see —
# HF_HUB_OFFLINE is honoured by huggingface_hub, not by our code — and
# demanding that our source mention it would turn a correct manifest
# red. Said out loud because it is the boundary of what this measures.
#
# On the source side comments are DROPPED before searching. A name that
# survives only inside a paragraph explaining it is not a name anything
# reads, and this house has already paid for scans that could not tell
# prose from code.
import pathlib
import re
import sys

import yaml

raiz = pathlib.Path(sys.argv[1])
base = raiz / "seed" / "platform"
manifiestos = sorted((base / "k8s" / "base" / "ai-system").glob("*.yaml"))

CODIGO = {".py", ".sh", ".go", ".js", ".mjs", ".ts"}


def leido_por(dirfuente):
    """Every identifier the sources under a directory really read."""
    texto = []
    for f in sorted(dirfuente.rglob("*")):
        if not f.is_file() or f.suffix not in CODIGO:
            continue
        try:
            crudo = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        texto.append("\n".join(l for l in crudo.splitlines()
                               if not re.match(r"^\s*#", l)))
    return "\n".join(texto)


malo = []
n_par = 0
n_env = 0

for m in manifiestos:
    fuente = base / "ai" / m.stem
    if not fuente.is_dir():
        continue                      # its code does not live in this seed
    n_par += 1
    cuerpo = leido_por(fuente)
    if not cuerpo.strip():
        malo.append(f"{m.name} pairs with ai/{m.stem}/ and no source there could be read: "
                    f"this check cannot tell a live variable from a dead one for that lane")
        continue
    try:
        docs = list(yaml.safe_load_all(m.read_text(encoding="utf-8")))
    except yaml.YAMLError as e:
        malo.append(f"{m.name} does not parse as YAML ({e}) and its variables could not be read")
        continue
    for d in docs:
        if not isinstance(d, dict):
            continue
        spec = (((d.get("spec") or {}).get("template") or {}).get("spec")) or {}
        for c in (spec.get("containers") or []):
            for e in (c.get("env") or []):
                nombre = (e or {}).get("name", "")
                if not nombre.startswith("AEGIS_"):
                    continue
                n_env += 1
                if not re.search(rf"\b{re.escape(nombre)}\b", cuerpo):
                    malo.append(
                        f"{m.name} sets {nombre} for container {c.get('name','?')} and nothing "
                        f"under ai/{m.stem}/ reads that name: the setting is inert, the code "
                        f"falls back to its default, and the pod comes up Ready saying nothing "
                        f"about it")

for l in malo:
    print(l)
print(f"__COUNT__ {n_par} {n_env}", file=sys.stderr)
