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

def screens_of(readings):
    from aegis import screens
    subject = next((r["comando"].split()[-1] for r in readings
                    if (r.get("comando") or "").startswith("tenant show ")), None)
    out = {"projects": console.render(readings)}
    for view in getattr(screens, "VIEWS", {}) or {}:
        if view != "projects":
            out[view] = console.render(readings, view=view)
    if subject:
        out["project"] = console.render(readings, subject=subject)
    return out


cases = sorted(d for d in os.listdir(CASES) if os.path.isdir(os.path.join(CASES, d))) \
    if os.path.isdir(CASES) else []
drawn = 0
for name in cases:
    try:
        readings = console.readings_of_case(os.path.join(CASES, name))
        pages = screens_of(readings)
    except Exception as e:                                # noqa: BLE001
        print(f"case {name} cannot be rendered ({type(e).__name__}: {e})")
        continue
    # Since 2026-09-17 the first screen carries no numbers: each
    # reading is drawn as a source on the screen it belongs to. So the
    # rule is held on EVERY screen — what a screen draws it dates, and
    # the age is on the page once per source — and across them: every
    # reading is drawn as a source somewhere.
    dated = set()
    for view, html in pages.items():
        sources = re.findall(r'<section class="[^"]*\bsource\b[^"]*"[^>]*>', html)
        ages = len(re.findall(r'class="age"', html))
        if ages != len(sources):
            print(f"case {name}, screen {view}: {len(sources)} source(s) drawn and {ages} age(s) "
                  f"visible on the page")
        for tag in sources:
            drawn += 1
            cmd = re.search(r'data-command="([^"]*)"', tag)
            if "data-measured-at=" not in tag:
                print(f"case {name}, screen {view}: the source {cmd.group(1) if cmd else '?'!r} is "
                      f"drawn with no data-measured-at: a measurement with no age is read as "
                      f"if it were now")
            elif cmd:
                dated.add(cmd.group(1))
    for r in readings:
        if r["comando"] not in dated:
            print(f"case {name}: `{r['comando']}` is drawn on no screen as a dated source")

print(f"SCOPE: {len(cases)} case(s) rendered through every screen, {drawn} source(s) drawn")
