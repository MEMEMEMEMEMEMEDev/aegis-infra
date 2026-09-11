"""Check 122 — the console does not flatten.

Two invariants, asserted over EVERY case of the corpus, by rendering it
for real and reading the result. They are asserted on ATTRIBUTES and
never on words, so the language of the interface does not tie the suite.

  I-1  no state is lost and none is invented: every distinct state the
       documents carry reaches the screen, and every state on the screen
       comes from the documents.
  I-2  the rc is honoured: a reading that could not be evaluated, or
       that gave back no document at all, can never end in a verdict
       that says everything is fine.

Plus one static rule that holds the other two up: the map from the
producers' words to the screen's must be TOTAL, and it may never send a
word that means «could not look» to one that means «fine» — and which
words those are is read from lib/aegis/outcomes.py, not decided here.
"""
import html as _htmllib
import os
import re
import sys


def _unescape(text):
    return _htmllib.unescape(text)

sys.path.insert(0, os.path.join(sys.argv[1], "lib"))

ROOT = sys.argv[1]
CASES = os.path.join(ROOT, "console", "cases")

try:
    from aegis import console, outcomes
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/console.py cannot be imported ({e}): the console has no renderer "
          f"and nothing could be asserted about what it draws")
    sys.exit(0)

SCREEN = getattr(console, "SCREEN", None)
if not isinstance(SCREEN, dict) or not SCREEN:
    print("lib/aegis/console.py exposes no SCREEN map: there is no declared translation "
          "from the words the producers speak to the ones the screen shows")
    sys.exit(0)

# ── the map is total, and it does not lie ────────────────────────────
# The producers' vocabulary, derived exactly as check 125 derives it.
def code(path):
    try:
        return "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                         if not l.lstrip().startswith("#"))
    except OSError:
        return ""

house = dict(getattr(outcomes, "RC", {}))
words = set(house)
rnd = code(os.path.join(ROOT, "libexec", "aegis-check"))
# NOT EVERY `_rec` KIND IS A STATE. The round files four kinds of thing
# and only two of them are verdicts: `section` opens a section and
# `note` hangs a line off the measure above it. Both are handled by
# name in the renderer of the document, and that is exactly where this
# derivation reads which ones they are — asking for a translation of
# «section» would be demanding the screen show a state nobody emits.
special = set(re.findall(r'kind\s*==\s*"([a-z-]+)"', rnd))
own = set(re.findall(r"_rec\s+([a-z-]+)\b", rnd)) - special
words |= own
# The round translates its own words into the house's, in its own
# source. That line is where a round word inherits an rc.
for a, b in re.findall(r'"([a-z-]+)":\s*(ALREADY|WRONG|NOT_EVALUABLE)\b', rnd):
    house[a] = getattr(outcomes, b, None) and outcomes.RC[getattr(outcomes, b)]
for word in sorted(words):
    if word not in SCREEN:
        print(f"the producers can emit the state {word!r} and SCREEN does not translate it: "
              f"a word with no translation is a state the screen cannot show")
        continue
    rc = house.get(word)
    if rc == 2 and console.LOOKED_AT.get(SCREEN[word], True):
        print(f"SCREEN sends {word!r} — which means «could not look» (rc 2) — to "
              f"{SCREEN[word]!r}, and that is a state the screen counts as looked at: "
              f"this is the flattening the product exists to eliminate")

# ── and every case, rendered and read back ───────────────────────────
ATTR = re.compile(r'data-state="([a-z-]+)"')

def states_in(readings):
    """Every state word the documents of a reading carry."""
    found = set()
    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k == "state" and isinstance(v, str):
                    found.add(v)
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    for r in readings:
        walk(r.get("documento"))
    return found

cases = sorted(d for d in os.listdir(CASES) if os.path.isdir(os.path.join(CASES, d))) \
    if os.path.isdir(CASES) else []
for name in cases:
    try:
        readings = console.readings_of_case(os.path.join(CASES, name))
        html = console.render(readings)
    except Exception as e:                                # noqa: BLE001
        print(f"case {name} cannot be rendered ({type(e).__name__}: {e}): a case the console "
              f"cannot draw is a state of the world it would meet blind")
        continue

    # I-1 also means NO READING DISAPPEARS. A page can name the right
    # states at the top and still drop the source that could not be
    # looked at, and then the operator knows something is unseen and
    # not WHICH thing — which is the same loss one step later. Found by
    # this check's own tooth red_6, which made a blind reading draw
    # nothing while the verdict still said «unseen».
    drawn = set(re.findall(r'data-command="([^"]*)"', html))
    for r in readings:
        if _unescape(r["comando"]) not in {_unescape(d) for d in drawn}:
            print(f"case {name}: `{r['comando']}` was consulted and no element of the screen "
                  f"is about it (I-1): the reading vanished, whatever its answer was")

    on_screen = set(ATTR.findall(html))
    expected = {SCREEN[s] for s in states_in(readings) if s in SCREEN}
    # A reading with no document is a state of the world too, and the
    # screen has to say so.
    if any(r.get("sin_documento") for r in readings):
        expected.add(console.UNSEEN)

    for lost in sorted(expected - on_screen):
        print(f"case {name}: the documents carry {lost!r} and no element of the screen shows it "
              f"(I-1): a state that does not reach the screen was flattened on the way")
    for invented in sorted(on_screen - expected):
        print(f"case {name}: the screen shows {invented!r} and no document carries it (I-1)")

    # I-2 · the verdict cannot be kinder than the readings.
    verdict = re.search(r'data-veredicto="([a-z-]+)"', html)
    if not verdict:
        print(f"case {name}: the rendered page declares no data-veredicto: there is no single "
              f"place that says how the whole thing is (I-2)")
        continue
    blind = any(r.get("sin_documento") or r.get("rc") == 2 for r in readings)
    wrong = any(r.get("rc") == 1 for r in readings)
    if blind and console.LOOKED_AT.get(verdict.group(1), True):
        print(f"case {name}: something could not be evaluated and the verdict is "
              f"{verdict.group(1)!r}, which counts as looked at (I-2)")
    elif wrong and console.IS_FINE.get(verdict.group(1), False):
        print(f"case {name}: a reading came back wrong (rc 1) and the verdict is "
              f"{verdict.group(1)!r}, which says everything is fine (I-2)")

print(f"SCOPE: {len(cases)} case(s) rendered, {len(words)} producer word(s) against "
      f"{len(SCREEN)} translation(s)")
