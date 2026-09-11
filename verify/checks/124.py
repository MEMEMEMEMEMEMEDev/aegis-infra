"""Check 124 — the skin dresses every state, and the fourth one is never
told by colour alone.

Two guarantees, both about the moment a measurement becomes something a
person sees:

  1. TOTALITY. Every word the screen can show has a rule in the skin. A
     state with no rule renders unstyled — which on a page full of
     coloured surfaces reads as «nothing here», and that is a state
     disappearing at the last possible step.

  2. THE FOURTH OUTCOME IS NOT A SHADE. «Could not look» has to be told
     apart from the others without colour: a hatch, a border, a shape.
     Every other state may be a colour and nothing else; this one may
     not, because it is the distinction the whole product is built to
     preserve, and colour is the one channel that fails on a printed
     page, a bad screen, or an eye that does not see red.

Which states exist is read from lib/aegis/console.py; which one means
«could not look» is read from its LOOKED_AT table. Neither is listed here.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
ROOT = sys.argv[1]
SKIN = os.path.join(ROOT, "share", "console", "sereno.css")

try:
    from aegis import console
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/console.py cannot be imported ({e}): nothing could be asked about the skin")
    sys.exit(0)

try:
    css = open(SKIN, encoding="utf-8").read()
except OSError:
    print(f"the console declares a skin at {os.path.relpath(SKIN, ROOT)} and the file is not "
          f"there: every state would render unstyled")
    sys.exit(0)

# Comments are prose, and prose is not a rule: a paragraph naming a
# state would otherwise vouch for a rule that does not exist.
code = re.sub(r"/\*.*?\*/", "", css, flags=re.S)

def bodies_for(state):
    return re.findall(rf'\[data-state="{re.escape(state)}"\][^{{]*\{{([^}}]*)\}}', code)


states = set(console.SCREEN.values()) | set(console.LOOKED_AT)
# DRESSED MEANS VISIBLE, not merely mentioned. The first version of this
# counted any rule at all, and the tooth deleted the surface of two
# states while leaving their `order:` lines behind — the skin still
# named them, and they still rendered as nothing. What makes a state
# visible is a surface or an ink.
dressed = {s for s in states
           if any(re.search(r"\b(background|color)\b", b) for b in bodies_for(s))}
for state in sorted(states):
    if state not in dressed:
        print(f"the skin gives the state {state!r} no surface and no ink: it would render "
              f"unstyled, which on this page reads as nothing being there")

# The one that may not be a colour. Derived: the state the console says
# was NOT looked at.
unseen = [s for s, looked in console.LOOKED_AT.items() if not looked]
for state in unseen:
    body = " ".join(bodies_for(state))
    # What tells it apart without colour: a pattern, a shape, an edge.
    # `background-image` is the hatch; `border-radius` the square dot;
    # `box-shadow: inset` the outline that survives a grayscale print.
    if not re.search(r"background-image|border-radius|box-shadow:\s*inset|border:", body):
        print(f"the skin tells {state!r} apart by colour alone: it is the one state that must "
              f"survive black and white, because confusing it with «fine» is the failure the "
              f"product exists to eliminate")

print(f"SCOPE: {len(states)} state(s) of the screen, {len(dressed)} dressed by the skin, "
      f"{len(unseen)} that may not be told by colour alone")
