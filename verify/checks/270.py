"""Check 270 — the console draws the books.

plan/21 stage 7 (2026-10-02): `aegis vulns` reads the books image-watch
keeps; the console is where the operator looks, and it did not show them.
It reads `vulns` now (SOURCES of libexec/aegis-console) and draws:
  · on Security, a section from that reading (data-command="vulns") with
    one row per image that owes something or could not be looked at,
    each with its state;
  · on each project's card, the worst state of its app images and how
    many findings they carry;
  · the menu's dot for Security, fed by the reading.
Debt inside its window is a `done` step: it is drawn FINE, with its date
in words. Drawing it `attention` would invent a state the document does
not carry (the doctrine the Updates page wrote for «behind»).
The sidecar renders console/cases/security-vulns and reads attributes.
"""
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1])
sys.path.insert(0, os.path.join(ROOT, "lib"))
findings = []
CASE = os.path.join(ROOT, "console", "cases", "security-vulns")
if not os.path.isdir(CASE):
    print("console/cases/security-vulns is missing: nothing shows the books are drawn")
    sys.exit(0)

from aegis import console, screens  # noqa: E402

src = open(os.path.join(ROOT, "libexec", "aegis-console"), encoding="utf-8").read()
m = re.search(r"^SOURCES = \((.*?)\)\n", src, re.S | re.M)
if not m or not re.search(r'^\s*"vulns",', m.group(1), re.M):
    findings.append("the console does not read `vulns` (SOURCES): the books never reach a screen")

readings = console.readings_of_case(CASE)
page = screens.security(readings)
sec = re.search(r'<section class="source vulns"[^>]*data-command="vulns"[^>]*>(.*?)</section>', page, re.S)
if not sec:
    findings.append("Security has no section drawn from the `vulns` reading")
else:
    body = sec.group(1)
    rows = {img: st for st, img in re.findall(r'<tr data-state="(\w+)"><td><i class="pip" data-state="\w+"></i></td><td>(?:<a[^>]*>|<span class="mono">)([^<]+)<', body)}
    want = {"shop/shop-stock": "wrong", "drop/drop-app": "unseen", "python": "fine", "shop/shop-api": "fine"}
    for img, st in want.items():
        if rows.get(img) != st:
            findings.append(f"Security draws {img} as {rows.get(img)!r}, not {st!r}")
    if "portafolio/portafolio-front" in rows:
        findings.append("an image scanned clean takes a row among what is owed (fine sinks, it does not stand)")
    if 'data-state="attention"' in body:
        findings.append("debt inside its window is drawn `attention`: a state the document does not carry")
    if "2026-10-29" not in body:
        findings.append("a debt's due date is not on the screen")

over = screens.overview(readings) if hasattr(screens, "overview") else ""
cards = {name: st for st, name in re.findall(r'<article class="card proj" data-state="(\w+)">.*?<h3><a href="/projects/([^"]+)"', over, re.S)}
if cards.get("shop") != "wrong":
    findings.append(f"the card of shop (an app past due) reads {cards.get('shop')!r}, not wrong")
if cards.get("drop") != "unseen":
    findings.append(f"the card of drop (an app nobody could scan) reads {cards.get('drop')!r}, not unseen")
if not re.search(r'<span class="kv" data-state="wrong"><span class="k">vulns</span>', over):
    findings.append("no project card carries its vulnerabilities as a chip")

dots = screens.page_states(readings)
if dots.get("security") != "unseen":
    findings.append(f"the menu's dot for Security is {dots.get('security')!r}: the books do not feed it")

for x in findings:
    print(x)
print("SCOPE: console/cases/security-vulns rendered — Security's section, the project cards and the menu's dots read by attribute")
