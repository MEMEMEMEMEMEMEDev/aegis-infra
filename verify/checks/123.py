"""Check 123 — the console reads documents, never prose.

Rule E-2 of the house: no state is communicated through prose. The
console is the first consumer built on top of the CLI, and the cheapest
wrong turn available to it is to run a command and look at the sentence
it printed. That is how `aegis-app` used to learn whether a webhook had
been created — by matching the words «webhook creado» — and a change of
wording broke the table on the other side.

Two rules, both derived:
  1. every aegis command the console invokes goes through
     `cli.run_json`, never `cli.run` and never a subprocess of its own;
  2. the console's source carries none of the narration's MARKERS —
     the symbols and sentences the round prints for people. Which ones
     those are is read from libexec/aegis-check, not listed here.
"""
import os
import re
import sys

ROOT = sys.argv[1]
SUBJECTS = [os.path.join(ROOT, "lib", "aegis", "console.py"),
            os.path.join(ROOT, "lib", "aegis", "screens.py"),
            os.path.join(ROOT, "libexec", "aegis-console")]


def code(path):
    try:
        return "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                         if not l.lstrip().startswith("#"))
    except OSError:
        return None


# The narration's markers, derived from the round that prints them.
rnd = code(os.path.join(ROOT, "libexec", "aegis-check")) or ""
markers = set()
for fn in ("ok", "bad", "notice"):
    m = re.search(rf"^{fn}\(\)\s*{{.*?printf '([^']*)'", rnd, re.M | re.S)
    if m:
        # ONLY WHAT DISTINGUISHES THE NARRATION. A lone ASCII sign is
        # not a marker of anything: `notice()` prints «!», and «!»
        # lives in every `!=` ever written. What identifies the prose
        # is its non-ASCII marks (the ✓ and the ✗) and its phrases.
        markers |= {t for t in re.findall(r"[^\s%s\\]+", m.group(1))
                    if t and not t.isalnum() and (len(t) >= 3 or not t.isascii())}
markers |= {w for w in re.findall(r'"(COULD NOT EVALUATE)[^"]*"', rnd)}

seen = 0
for path in SUBJECTS:
    src = code(path)
    if src is None:
        continue
    seen += 1
    rel = os.path.relpath(path, ROOT)
    # 1 · the only door to another command is the document
    if re.search(r"\bcli\.run\(", src):
        print(f"{rel} calls cli.run(): that hands back the NARRATION, and whatever it does "
              f"with it is reading prose")
    if re.search(r"subprocess\.[a-z_]+\(\s*\[[^]]*\baegis\b", src):
        print(f"{rel} invokes an aegis command through subprocess instead of cli.run_json: "
              f"the output it gets is text, and the contract is a document")
    # 2 · and it does not carry the narration's marks.
    #     AN ESCAPED MARK IS THE SAME MARK: `"\u2713" in line` matches
    #     the very tick the round prints, and a check that only looks
    #     for the character would vouch for it. Found by this check's
    #     own tooth, which wrote exactly that.
    decoded = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), src)
    for marker in sorted(markers):
        if marker and (marker in src or marker in decoded):
            print(f"{rel} carries the narration's marker {marker!r}: the console either "
                  f"reproduces the prose or matches on it, and both are rule E-2")

print(f"SCOPE: {seen} file(s) of the console against {len(markers)} marker(s) of the narration")
