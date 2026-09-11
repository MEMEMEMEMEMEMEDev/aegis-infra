"""Check 119 — every case declares where it came from, and a derived one
reproduces from its base.

Prints one line per problem; silence is a pass.
"""
import json
import os
import re
import sys

import yaml

ROOT = sys.argv[1]
CASES = os.path.join(ROOT, "console", "cases")
NAME = re.compile(r"^[a-z][a-z0-9-]{2,39}$")
PROVENANCE = ("medido", "derivado", "sintetico")
problems = []


def die(msg):
    print(msg)


def load(name):
    return yaml.safe_load(open(os.path.join(CASES, name, "case.yaml"), encoding="utf-8")) or {}


names = sorted(d for d in os.listdir(CASES) if os.path.isdir(os.path.join(CASES, d)))
for name in names:
    where = f"console/cases/{name}"
    path = os.path.join(CASES, name, "case.yaml")
    if not os.path.isfile(path):
        die(f"{where}/ has no case.yaml: a directory of documents nobody can date or attribute")
        continue
    try:
        case = load(name)
    except yaml.YAMLError as e:
        die(f"{where}/case.yaml does not parse: {e}")
        continue

    if case.get("caso") != name:
        die(f"{where}/case.yaml calls itself {case.get('caso')!r} and lives in {name!r}: "
            "two names for one case is one name too many")
    if not NAME.match(name):
        die(f"{where}: the name must be [a-z][a-z0-9-]{{2,39}}")
    if not (case.get("que") or "").strip():
        die(f"{where} does not say WHAT state of the world it is: a corpus of unlabelled "
            "documents is a corpus nobody can choose from")

    prov = case.get("procedencia")
    if prov not in PROVENANCE:
        die(f"{where} declares procedencia {prov!r}, and it has to be one of {', '.join(PROVENANCE)}: "
            "a case with no provenance is indistinguishable from one somebody invented")
        continue

    # EVERY case says how to READ it, whatever its provenance. A
    # derived case that lists a mutation and no `producido_por` carries
    # documents nobody can load: it renders as an empty screen, which
    # is a state of the world it never claimed to be. Found by check
    # 122 the first time it rendered the corpus.
    if prov in ("medido", "derivado", "sintetico") and not case.get("producido_por"):
        die(f"{where} declares no `producido_por`: nothing says which command each document "
            "answers, so the case cannot be read back")

    if prov == "medido":
        # The three facts that make a measurement repeatable: what was
        # run, when, and against which product. Without them «medido» is
        # a word.
        for field in ("producido_por", "medido_en", "aegis"):
            value = case.get(field)
            if not value:
                die(f"{where} is `medido` and does not declare `{field}`: "
                    "a measurement nobody can date or reproduce is a claim")
            # AND THE COMMIT HAS TO BE TEXT. YAML reads an unquoted sha
            # of forty zeros as the integer 0, which then passes for
            # «declared» and matches nothing. Found by this check's own
            # control, which wrote exactly that.
            #
            # `medido_en` is NOT asked the same question, and the same
            # control is why: an unquoted timestamp becomes a datetime,
            # and a datetime is a perfectly good date — more comparable
            # than the string, not less. Demanding text there was the
            # rule being wider than the guarantee.
            elif field == "aegis" and not isinstance(value, str):
                die(f"{where} declares `aegis` as {type(value).__name__} and not as text: "
                    "a commit that YAML turned into a number matches no commit")
        for entry in case.get("producido_por") or []:
            cmd = entry.get("comando")
            if not cmd:
                die(f"{where} has an entry of producido_por with no `comando`")
                continue
            doc, absent = entry.get("documento"), entry.get("sin_documento")
            if doc and absent:
                die(f"{where}: `{cmd}` declares a document AND a reason for having none")
            elif doc:
                if not os.path.isfile(os.path.join(CASES, name, "documents", doc)):
                    die(f"{where}: `{cmd}` names documents/{doc} and the file is not there")
            elif not absent:
                die(f"{where}: `{cmd}` produced neither a document nor a reason for having none — "
                    "which is the silence this whole corpus exists to make impossible")

    if prov == "sintetico" and not (case.get("por_que") or "").strip():
        die(f"{where} is `sintetico` and does not say WHY the real state cannot be reached: "
            "that sentence is the only thing separating a deliberate exception from a fabrication")

    if prov == "derivado":
        base = case.get("derivado_de")
        if not base:
            die(f"{where} is `derivado` and does not name `derivado_de`")
            continue
        if not os.path.isfile(os.path.join(CASES, base, "case.yaml")):
            die(f"{where} derives from {base!r} and that case does not exist")
            continue
        mutation = case.get("mutacion") or []
        if not mutation:
            die(f"{where} is `derivado` and records no `mutacion`: "
                "a derivation nobody can replay is a hand edit with a nicer name")
            continue
        # THE DERIVATION IS REPLAYED, not believed. Same discipline as a
        # tooth: apply what is written and demand the exact result.
        for step in mutation:
            doc = step.get("documento")
            src = os.path.join(CASES, base, "documents", doc or "")
            dst = os.path.join(CASES, name, "documents", doc or "")
            if not doc or not os.path.isfile(src) or not os.path.isfile(dst):
                die(f"{where}: the mutation names documents/{doc} and it is missing "
                    f"from the base or from here")
                continue
            text = open(src, encoding="utf-8").read()
            frm, to = step.get("de"), step.get("a")
            if frm is None or to is None:
                die(f"{where}: a step of the mutation has no `de`/`a`")
                continue
            if text.count(frm) != 1:
                die(f"{where}: `{frm}` appears {text.count(frm)} time(s) in the base's {doc} "
                    "and a replayable mutation has to match exactly once")
                continue
            text = text.replace(frm, to, 1)
            if text != open(dst, encoding="utf-8").read():
                die(f"{where}: replaying the recorded mutation over {base}/{doc} does NOT "
                    "reproduce this case — the document was edited by hand beyond what it declares")

print("", end="")
