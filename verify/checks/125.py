"""Check 125 — the vocabulary a case pins is still a vocabulary the
product can emit.

The corpus freezes VALUES on purpose: a case says «this is how the
world looked that day» and that stays true forever. What may not age in
silence is the CONTRACT — the words. So each case records, per
document, the top-level keys and every `state` word it carried, and
this check re-derives that vocabulary from the producers and demands
the pinned one be a subset.

The producers, derived and not listed:
  · lib/aegis/outcomes.py — the four states of the house and the two
    keys of its document
  · libexec/aegis-check   — the round's own measure vocabulary and the
    extra keys of its document

Prints one line per problem, then a SCOPE line.
"""
import os
import re
import sys

import yaml

ROOT = sys.argv[1]
CASES = os.path.join(ROOT, "console", "cases")
OUTCOMES = os.path.join(ROOT, "lib", "aegis", "outcomes.py")
ROUND = os.path.join(ROOT, "libexec", "aegis-check")


def code(path):
    """The file without whole-line comments: prose is not vocabulary."""
    try:
        return "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                         if not l.lstrip().startswith("#"))
    except OSError:
        return None


out, rnd = code(OUTCOMES), code(ROUND)
if out is None:
    print(f"SCOPE: {os.path.relpath(OUTCOMES, ROOT)} is not there — the vocabulary of the "
          f"house could not be derived and nothing was compared")
    sys.exit(0)

# The four outcomes, from the only place that defines them.
states = set(re.findall(r'^\s*[A-Z_]+\s*=\s*"([a-z-]+)"', out, re.M))
keys = set(re.findall(r'json\.dump\(\{\s*"([a-z]+)"', out)) | {"steps", "rc"}
if rnd:
    # The round files its measures with its own words, and its document
    # carries two counters of its own.
    # The round's OWN words (the ones its measures carry). The four of
    # the house are not re-harvested here: aegis-check imports them
    # from outcomes.py, which is the whole point — a list written twice
    # is a list that drifts, and that is the drift this check hunts.
    states |= set(re.findall(r'_rec\s+([a-z-]+)\b', rnd))
    keys |= set(re.findall(r'json\.dump\(\{"([a-z]+)"', rnd))
    keys |= set(re.findall(r'"(steps|failures|notices|rc)":', rnd))

problems = 0
pinned_states, pinned_keys = set(), set()
for name in sorted(d for d in os.listdir(CASES) if os.path.isdir(os.path.join(CASES, d))):
    path = os.path.join(CASES, name, "case.yaml")
    if not os.path.isfile(path):
        continue
    case = yaml.safe_load(open(path, encoding="utf-8")) or {}
    for doc, shape in (case.get("forma") or {}).items():
        for word in shape.get("estados") or []:
            pinned_states.add(word)
            if word not in states:
                problems += 1
                print(f"console/cases/{name} pins the state {word!r} for {doc} and no producer "
                      f"emits that word any more: the case is older than the contract")
        for key in shape.get("claves") or []:
            pinned_keys.add(key)
            if key not in keys:
                problems += 1
                print(f"console/cases/{name} pins the top-level key {key!r} for {doc} and no "
                      f"producer writes it any more: the case is older than the contract")

print(f"SCOPE: {len(pinned_states)} state word(s) and {len(pinned_keys)} document key(s) pinned "
      f"by the corpus, against {len(states)} and {len(keys)} the producers still emit")
