"""Check 213 — every class of pin is owned by a layer, and every layer is
judged by sections the round actually has.

TWO LISTS THAT CANNOT BE ALLOWED TO DRIFT.

The first is the classes of pin, which `pins.py` derives from the tree.
The second is the layers, which `window.py` writes down because they are
a property of the PROTOCOL and not of the artifact — nothing in the
platform says that charts come after k3s. Written down is fine; written
down and then quietly out of step with the other is not. A class nobody
gave a layer is a class a window walks straight past: the inventory
reports it as behind, the plan proposes it, and the window never touches
it, month after month, saying «accepted» every time.

The third join is the one that would rot in silence. Each layer names
the sections of the round it is judged by, and the round's sections are
its own — `heading` in `aegis-check`. A layer that names a section that
no longer exists is a layer whose acceptance reads an empty set and
passes ALWAYS. That is the failure this file exists for: not a red
verdict, a green one that means nothing.
"""
import os
import re
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
os.environ["AEGIS_ROOT"] = ROOT
findings = []

try:
    from aegis import pins, window as win
except Exception as e:                                    # noqa: BLE001
    print(f"the layers or the classes cannot be imported ({e}): they were not joined")
    print("SCOPE: nothing was joined")
    sys.exit(0)

CHECK = os.path.join(ROOT, "libexec", "aegis-check")
if not os.path.isfile(CHECK):
    print("SCOPE: there is no round to read the sections from")
    sys.exit(0)

# ── the seed's userland pins, read here and not asked of anybody ─────
pins_gv = {}
GV = os.path.join(ROOT, "seed", "platform", "ansible", "inventory", "group_vars",
                  "all.yml")
if os.path.isfile(GV):
    gv = open(GV, encoding="utf-8").read()
    um = re.search(r"^userland_pins:\s*$", gv, re.M)
    if um:
        for line in gv[um.end():].splitlines():
            if line.strip() and not line.startswith((" ", "\t", "#")):
                break
            pm = re.match(r"^\s+([a-z0-9_]+):\s*[\"']?([^\"'\s#]+)", line)
            if pm:
                pins_gv[pm.group(1)] = pm.group(2)

# ── the round's own sections, derived from the round ─────────────────
body = "\n".join(ln for ln in open(CHECK, encoding="utf-8").read().splitlines()
                 if not ln.lstrip().startswith("#"))
sections = set(re.findall(r'^\s*heading\s+"([^"]+)"', body, re.M))
if not sections:
    findings.append("no section of the round could be read: the join between a layer and "
                    "what judges it could not be made at all")

# ── every class is owned by exactly one layer ────────────────────────
owned = {}
for layer in win.LAYERS:
    for cls in layer.classes:
        if cls in owned:
            findings.append(f"the class {cls!r} is claimed by layers {owned[cls]} and "
                            f"{layer.number}: a change would be applied twice and "
                            f"reverted once")
        owned[cls] = layer.number
for cls in sorted(pins.CLASSES):
    if cls not in owned:
        findings.append(f"no layer owns the class {cls!r}: the inventory reports it as "
                        f"behind, the plan proposes it, and a window walks past it every "
                        f"month while saying «accepted»")
for cls in sorted(owned):
    if cls not in pins.CLASSES:
        findings.append(f"layer {owned[cls]} owns the class {cls!r} and the inventory "
                        f"cannot produce it: the layer has no subject")

# ── the layer number a class carries agrees with the layer that owns it
for cls, meta in sorted(pins.CLASSES.items()):
    if cls in owned and meta.get("layer") != owned[cls]:
        findings.append(f"{cls!r} says it belongs to layer {meta.get('layer')} and layer "
                        f"{owned[cls]} is the one that applies it: the plan and the "
                        f"window would disagree about the order")

# ── every layer is judged by sections the round has ──────────────────
for layer in win.LAYERS:
    if not layer.sections:
        findings.append(f"layer {layer.number} ({layer.name}) names no section: its "
                        f"acceptance reads nothing and passes always")
    for sec in layer.sections:
        if sections and sec not in sections:
            findings.append(f"layer {layer.number} is judged by the section {sec!r} and "
                            f"the round has no such section: its acceptance compares an "
                            f"empty set and is green whatever happens")
    if not layer.undo:
        findings.append(f"layer {layer.number} ({layer.name}) does not say how it comes "
                        f"undone")
    if not isinstance(layer.minutes, int) or layer.minutes <= 0:
        findings.append(f"layer {layer.number} has no time estimate: the budget cannot "
                        f"refuse to start it and it would begin with no room left")

# ── the numbers are the ones the protocol walks ──────────────────────
numbers = [l.number for l in win.LAYERS]
if numbers != sorted(numbers) or len(set(numbers)) != len(numbers):
    findings.append(f"the layers are not in order or repeat a number: {numbers}")

# ── and the command applies every one of them ────────────────────────
upd = open(os.path.join(ROOT, "libexec", "aegis-update"), encoding="utf-8").read()
applied = set(int(n) for n in re.findall(r"if layer\.number == (\d+):", upd))
last = re.search(r"return layer_(\w+)\(ctx, layer\)", upd)
if last:
    applied.add(max(numbers))
for n in numbers:
    if n not in applied:
        findings.append(f"layer {n} is declared and `run_layer` has no branch for it: it "
                        f"would be counted, priced against the budget, and do nothing")

# ══════════════════════════════════════════════════════════════════════
#  and the two decisions that actually stop a window, driven
# ══════════════════════════════════════════════════════════════════════
# The joins above are about lists. These two are about what happens when
# the lists are used, and they are the only two things in the whole walk
# that decide whether it carries on.


def _round(**sections_):
    return {"steps": [{"step": name,
                       "measures": [{"measure": m, "state": st} for m, st in ms]}
                      for name, ms in sections_.items()]}


layer4 = [l for l in win.LAYERS if l.number == 4][0]
before = _round(**{"argocd": [("every app is Synced", "good")],
                   "pods": [("no pod restarts", "good")],
                   "every push built": [("the last push built", "good")]})

# a failure INSIDE the layer's sections stops it
after_mine = _round(**{"argocd": [("every app is Synced", "bad")],
                       "pods": [("no pod restarts", "good")],
                       "every push built": [("the last push built", "good")]})
v = win.accept_layer(layer4, before, after_mine)
if v["acepta"]:
    findings.append("a new failure in a section the layer is judged by was accepted: the "
                    "walk would carry on standing on something that just broke")

# a failure OUTSIDE them does not
after_theirs = _round(**{"argocd": [("every app is Synced", "good")],
                         "pods": [("no pod restarts", "good")],
                         "every push built": [("the last push built", "bad")]})
v = win.accept_layer(layer4, before, after_theirs)
if not v["acepta"]:
    findings.append("a failure in a section this layer is NOT judged by stopped it: every "
                    "layer would answer for the one before it, and the rollback would "
                    "undo something that was not the cause")
if v.get("fuera_de_capa") != 1:
    findings.append(f"a failure outside the layer was not counted as outside it: {v}")

# a reading that was fine and can no longer be taken is a failure too
after_blind = _round(**{"argocd": [("every app is Synced", "not-evaluated")],
                        "pods": [("no pod restarts", "good")],
                        "every push built": [("the last push built", "good")]})
if win.accept_layer(layer4, before, after_blind)["acepta"]:
    findings.append("a reading that was fine and that nobody could take afterwards was "
                    "accepted: a layer that blinds a measurement has not passed it, it "
                    "has stopped asking")

# ── the budget refuses to START, and never cuts short ────────────────
import time as _t
b = win.Budget(minutes=10, started=_t.time())
if b.room_for(layer4):
    findings.append(f"a budget of 10 minutes says there is room for a layer that costs "
                    f"{layer4.minutes}: a window would begin a chart walk it cannot finish")
b2 = win.Budget(minutes=240, started=_t.time())
if not b2.room_for(layer4):
    findings.append("a fresh four-hour budget has no room for the longest layer")
b3 = win.Budget(minutes=240, started=_t.time() - 235 * 60)
if b3.room_for(layer4):
    findings.append("a budget with five minutes left still says there is room for an hour")

# ── the one refusal that protects an instance, not the artifact ──────
# Layer 2's pins are only real if phase 05 downloads that tool by
# version. A tool it hands to apt carries a number nobody delivers, and
# a window would commit the bump before finding out. The window asks
# the phase; if the phase cannot be read the answer is None and nothing
# is refused on that ground — but an EMPTY answer would be a refusal
# that silently never fires, which is the shape worth guarding.
downloads = win.host_downloads(ROOT)
if downloads is None:
    findings.append("the window cannot read which tools phase 05 downloads by version: "
                    "layer 2 would propose bumps the phase installs with apt and refuses "
                    "three commits later")
elif not downloads:
    findings.append("the window reads ZERO tools as downloaded by version: the refusal "
                    "that protects layer 2 would never fire, and it would look like it "
                    "was working")
else:
    for tool in sorted(downloads):
        if pins_gv.get(tool) == "apt":
            findings.append(f"the window believes phase 05 downloads {tool!r} by version "
                            f"and group_vars pins it `apt`: layer 2 would propose a bump "
                            f"of a number nobody delivers")

upd_code = "\n".join(ln for ln in upd.splitlines() if not ln.lstrip().startswith("#"))
if "host_downloads" not in upd_code:
    findings.append("the window never asks which tools the phase downloads: a layer 2 "
                    "bump of an apt-managed tool would be written, committed, handed to "
                    "the phase and refused there")
if "room_for" not in upd_code:
    findings.append("the window never asks the budget whether there is room: the estimate "
                    "is written down and nothing reads it")

for f in findings:
    print(f)
print(f"SCOPE: {len(win.LAYERS)} layer(s) against {len(pins.CLASSES)} class(es) of pin "
      f"and {len(sections)} section(s) of the round, plus 4 acceptances and 3 budgets "
      f"driven")
