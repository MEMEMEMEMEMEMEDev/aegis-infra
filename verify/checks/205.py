"""Check 205 — every screen of the console keeps the invariants, not
only the first one.

Checks 122 and 127 render the overview of every case. The console has
nine screens and a page per project now, each drawn from the same
readings by the same rule, and a rule that is only measured on one
screen is a rule the other eight can break quietly. So every case is
rendered through every view, and the project page for the cases that
carry a project's readings, and each result is read back:

  · no state on the screen that no document carries (I-1, invention);
  · every source drawn carries when it was read, and its age is on the
    page, once per source;
  · every source is about a command that was actually consulted;
  · the verdict at the top is never kinder than the readings (I-2).

What a concept page does NOT have to do is draw every reading: it draws
what is its own. Losing a reading is measured on the overview by 122.
"""
import html as _htmllib
import os
import re
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
ROOT = sys.argv[1]
CASES = os.path.join(ROOT, "console", "cases")

try:
    from aegis import console, screens
except Exception as e:                                    # noqa: BLE001
    print(f"the console cannot be imported ({e}): no screen could be rendered")
    sys.exit(0)

SCREEN = console.SCREEN
ATTR = re.compile(r'data-state="([a-z-]+)"')


def states_in(readings):
    found = set()
    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k == "state" and isinstance(v, str):
                    found.add(v)
                if k == "links" and isinstance(v, dict):
                    found.update(x for x in v.values() if isinstance(x, str))
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    for r in readings:
        walk(r.get("documento"))
    return found


cases = sorted(d for d in os.listdir(CASES) if os.path.isdir(os.path.join(CASES, d))) \
    if os.path.isdir(CASES) else []
views = list(getattr(screens, "VIEWS", {}) or {})
if not views:
    print("lib/aegis/screens.py declares no VIEWS: there is no screen to hold to the rule")
    sys.exit(0)
drawn = 0
for name in cases:
    readings = console.readings_of_case(os.path.join(CASES, name))
    subject = next((r["comando"].split()[-1] for r in readings
                    if (r.get("comando") or "").startswith("tenant show ")), None)
    expected = {SCREEN[s] for s in states_in(readings) if s in SCREEN}
    if any(r.get("sin_documento") for r in readings):
        expected.add(console.UNSEEN)
    commands = {_htmllib.unescape(r["comando"]) for r in readings}
    blind = any(r.get("sin_documento") or r.get("rc") == 2 for r in readings)
    wrong = any(r.get("rc") == 1 for r in readings)
    for view in views + (["project"] if subject else []):
        try:
            html = (console.render(readings, subject=subject) if view == "project"
                    else console.render(readings, view=view))
        except Exception as e:                            # noqa: BLE001
            print(f"case {name}, screen {view}: cannot be rendered ({type(e).__name__}: {e})")
            continue
        drawn += 1
        where = f"case {name}, screen {view}"
        for invented in sorted(set(ATTR.findall(html)) - expected):
            print(f"{where}: shows {invented!r} and no document carries it (I-1)")
        sources = re.findall(r'<section class="[^"]*\bsource\b[^"]*"[^>]*>', html)
        ages = len(re.findall(r'class="age"', html))
        if ages != len(sources):
            print(f"{where}: {len(sources)} source(s) drawn and {ages} age(s) on the page")
        for tag in sources:
            if "data-measured-at=" not in tag:
                print(f"{where}: a source is drawn with no data-measured-at")
            cmd = re.search(r'data-command="([^"]*)"', tag)
            if not cmd or _htmllib.unescape(cmd.group(1)) not in commands:
                print(f"{where}: a source is drawn about {cmd.group(1) if cmd else 'nothing'!r}, "
                      f"which was not consulted")
        verdict = re.search(r'data-veredicto="([a-z-]+)"', html)
        if not verdict:
            print(f"{where}: no data-veredicto: nothing says how the whole thing is (I-2)")
            continue
        if blind and console.LOOKED_AT.get(verdict.group(1), True):
            print(f"{where}: something could not be evaluated and the verdict is "
                  f"{verdict.group(1)!r}, which counts as looked at (I-2)")
        elif wrong and console.IS_FINE.get(verdict.group(1), False):
            print(f"{where}: a reading came back wrong and the verdict is "
                  f"{verdict.group(1)!r}, which says everything is fine (I-2)")

print(f"SCOPE: {len(cases)} case(s) through {len(views)} screen(s) and the project page: "
      f"{drawn} screen(s) rendered and read back")
