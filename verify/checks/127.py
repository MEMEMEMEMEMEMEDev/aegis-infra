"""Check 127 — no reading is drawn without saying when it was taken.

The oldest lie a dashboard tells is not a wrong number: it is a right
number from forty minutes ago, shown as if it were now. Nothing about
the screen looks off while somebody acts on it, which is what makes it
worse than an error.

So every source the console draws carries its own `data-measured-at`,
and when there is no time to carry it says THAT rather than leaving the
attribute off — an absent attribute is a question nobody asked.

The rule is checked by rendering every case of the corpus, which is
also where it finds the second half: a case whose documents have no
date renders with the age declared unknown, and that is correct.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
ROOT = sys.argv[1]
CASES = os.path.join(ROOT, "console", "cases")

try:
    from aegis import console
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/console.py cannot be imported ({e}): nothing could be asked about ages")
    sys.exit(0)

cases = sorted(d for d in os.listdir(CASES) if os.path.isdir(os.path.join(CASES, d))) \
    if os.path.isdir(CASES) else []
drawn = 0
for name in cases:
    try:
        readings = console.readings_of_case(os.path.join(CASES, name))
        html = console.render(readings)
    except Exception as e:                                # noqa: BLE001
        print(f"case {name} cannot be rendered ({type(e).__name__}: {e})")
        continue
    # `class="source ..."` and not `class="source"` exactly: the panel of
    # 2026-09-14 gave these elements a second class, and a check anchored
    # on the whole attribute went red over the ORDER of two words while
    # every reading was drawn with its age. What is being asked is
    # whether the element declares itself a drawn source, not how its
    # class list is spelled.
    sources = re.findall(r'<section class="[^"]*\bsource\b[^"]*"[^>]*>', html)
    if len(sources) != len(readings):
        print(f"case {name}: {len(readings)} reading(s) and {len(sources)} source(s) drawn")
    for tag in sources:
        drawn += 1
        cmd = re.search(r'data-command="([^"]*)"', tag)
        if "data-measured-at=" not in tag:
            print(f"case {name}: the source {cmd.group(1) if cmd else '?'!r} is drawn with no "
                  f"data-measured-at: a measurement with no age is read as if it were now")
    # And it is on the PAGE, not only in an attribute: an operator reads
    # the page, not the DOM.
    if len(re.findall(r'class="age"', html)) != len(readings):
        print(f"case {name}: {len(readings)} reading(s) and "
              f"{len(re.findall(r'class=.age.', html))} age(s) visible on the page")

print(f"SCOPE: {len(cases)} case(s) rendered, {drawn} source(s) drawn")
