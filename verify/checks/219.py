"""Check 219 — a step's payload cannot collide with a keyword beside it.

WITH A DATE ON IT: 2026-09-20, in the middle of a real update window,
with the maintenance page up and the sites off the air.

    steps.wrong("window:maintenance-no-effect", **seen,
                por_que="the hook ran and the public sites still answer…")

`seen` had just learned to carry its own `por_que`, so Python raised
`TypeError: got multiple values for keyword argument 'por_que'` and the
window died. The exit trap brought the page down and put the machine
back, which is the only reason that reads as a bug and not as an
incident — but the crash was a hundred lines of traceback where a
verdict should have been, and nothing had warned about it.

THE SHAPE OF THE TRAP. `f(**payload, key=value)` is fine right up until
the day something adds `key` to the payload, and the two are usually
written months apart by somebody thinking about different things. The
file carried twenty-one of them; two more were already live.

THE RULE, and it is blunt because blunt is what works here: a call that
emits a step or writes a journal entry may splat a dictionary, or name
keywords, and not both. `**{**payload, "key": value}` says the same
thing, cannot raise, and says out loud which one wins.
"""
import ast
import os
import pathlib
import sys

ROOT = sys.argv[1]
findings = []

#: The receivers whose keyword arguments are DATA rather than
#: parameters: everything they are handed ends up in a document.
SINKS = {"steps": ("done", "already", "wrong", "not_evaluable", "step"),
         "j": ("note", "close"), "ctx": ("say",)}

libexec = pathlib.Path(ROOT) / "libexec"
if not libexec.is_dir():
    print("SCOPE: there is no libexec")
    sys.exit(0)

files = sorted(p for p in libexec.iterdir() if p.is_file())
scanned, calls = 0, 0
for f in files:
    try:
        text = f.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        continue
    if not text.startswith("#!/usr/bin/env python3"):
        continue
    try:
        tree = ast.parse(text)
    except SyntaxError as e:
        findings.append(f"{f.name} does not parse ({e}): a file the verifier cannot read "
                        f"is one it cannot hold to anything")
        continue
    scanned += 1
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        if not (isinstance(fn, ast.Attribute) and isinstance(fn.value, ast.Name)):
            continue
        if fn.attr not in SINKS.get(fn.value.id, ()):
            continue
        calls += 1
        splat = [k for k in node.keywords if k.arg is None]
        named = [k.arg for k in node.keywords if k.arg is not None]
        if splat and named:
            findings.append(
                f"{f.name}:{node.lineno} {fn.value.id}.{fn.attr}() splats a dictionary "
                f"and also names {named}: the day that dictionary learns one of those "
                f"keys, this raises TypeError instead of emitting a verdict. Write "
                f"**{{**payload, \"key\": value}}, which cannot collide and says which "
                f"one wins")
        if len(splat) > 1:
            findings.append(
                f"{f.name}:{node.lineno} {fn.value.id}.{fn.attr}() splats {len(splat)} "
                f"dictionaries: two payloads sharing a key raise, and nothing here says "
                f"which was meant to win")

if not scanned:
    findings.append("no python command was read: this check had no subject and should "
                    "not be quietly green about it")
if not calls:
    findings.append("not one step-emitting call was found across the commands: either "
                    "the receivers were renamed or this check is looking at nothing")

for f in findings:
    print(f)
print(f"SCOPE: {calls} step-emitting call(s) across {scanned} python command(s)")
