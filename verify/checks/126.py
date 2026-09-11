"""Check 126 — every typeface the console carries is the one that was
pinned, and it travels with its licence.

Same protocol as mirror-images/images.txt, for the same reason: a URL is
a promise somebody else can break, so what is pinned is the CONTENT. The
bytes on disk are the ones that were read and reviewed, or this goes red.

Three questions, all derived from fonts.txt:
  · every file the manifest declares exists and hashes to what it says
  · every .woff2 on disk is declared — an unpinned font is one nobody
    looked at
  · every face travels with a licence beside it, because OFL requires it
    and because a font without one cannot be redistributed at all
"""
import hashlib
import os
import re
import sys

ROOT = sys.argv[1]
FONTS = os.path.join(ROOT, "share", "console", "fonts")
MANIFEST = os.path.join(FONTS, "fonts.txt")

try:
    lines = open(MANIFEST, encoding="utf-8").read().splitlines()
except OSError:
    print(f"the console carries fonts and {os.path.relpath(MANIFEST, ROOT)} is not there: "
          f"nothing says which bytes were meant to be here")
    sys.exit(0)

declared = {}
for line in lines:
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split()
    if len(parts) < 2:
        print(f"fonts.txt: the line {line[:40]!r} is not <file> <sha256> <url>")
        continue
    name, digest = parts[0], parts[1]
    declared[name] = digest
    path = os.path.join(FONTS, name)
    if not os.path.isfile(path):
        print(f"fonts.txt declares {name} and the file is not there: the page would fall back "
              f"to the system stack with nobody saying so")
        continue
    got = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if got != digest:
        print(f"{name} is NOT the font that was pinned: fonts.txt says {digest[:16]}… and the "
              f"file hashes to {got[:16]}… — these bytes were never reviewed")
    if not re.match(r"^[0-9a-f]{64}$", digest):
        print(f"fonts.txt pins {name} with something that is not a sha256: {digest[:20]!r}")

on_disk = sorted(f for f in os.listdir(FONTS) if f.endswith(".woff2")) if os.path.isdir(FONTS) else []
for name in on_disk:
    if name not in declared:
        print(f"{name} is in the tree and fonts.txt does not declare it: an unpinned font is "
              f"one nobody measured, and it ships to everybody who installs aegis")

# The licence has to travel WITH the file. OFL says so, and a face
# without one cannot legally be redistributed by anybody downstream.
licences = [f for f in os.listdir(FONTS) if f.upper().startswith("OFL")] if os.path.isdir(FONTS) else []
for name in on_disk:
    stem = name.replace("-latin.woff2", "").replace(".woff2", "")
    if not any(stem in lic for lic in licences):
        print(f"{name} travels with no licence beside it (expected an OFL naming {stem}): "
              f"the product is public and redistributes these bytes to everybody")

print(f"SCOPE: {len(declared)} face(s) pinned, {len(on_disk)} on disk, {len(licences)} licence(s)")
