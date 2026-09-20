"""Check 218 — the maintenance page is judged by asking the sites.

FOUR WINDOWS IN A ROW got this wrong, each in a different way, and the
four are worth naming because every one of them looked reasonable:

  1. it read the round the instant the hook returned — the tenant
     probes run every thirty seconds and had not run again;
  2. it counted only a reading that went from fine to NOT fine, and
     ignored one that DISAPPEARED, which is the commonest shape;
  3. it watched only readings that had been GREEN, and this instance's
     line about its sites was already a notice (two of five sit behind
     their own login);
  4. and then, with all of that fixed, the round's readings are keyed
     on the SHAPE of a sentence with its digits flattened — that is
     what makes two rounds comparable at all — so «1 of the 5 public
     site(s) do not answer» and «5 of the 5» are the same key with the
     same state, and the page's whole effect is that number.

The round is simply the wrong instrument: it measures the ORIGIN,
through probes, with a minute of lag, and the page lives at the EDGE.
So the window asks the public URLs itself, from the machine it runs on,
and compares against the codes it took as part of its photo.

What is demanded of the comparison is only that SOMETHING CHANGED.
aegis knows nothing about what the operator's page returns, and two of
these sites answer 302 on an ordinary day; the weakest true statement
is the right one here.

Everything below is driven with an injected clock and an injected
lookup: no network, no cluster, milliseconds.
"""
import os
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
os.environ["AEGIS_ROOT"] = ROOT
findings = []

try:
    from aegis import window as win
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/window.py cannot be imported ({e}): the reading was not driven")
    print("SCOPE: nothing was driven")
    sys.exit(0)

for name in ("effect_of_page", "public_urls", "reach"):
    if not hasattr(win, name):
        print(f"the window has no {name}: whether the maintenance page did anything is "
              f"decided somewhere that cannot be exercised without a network")
        print("SCOPE: nothing was driven")
        sys.exit(0)

#: The instance that found this: five sites, two of them answering 302
#: on an ordinary day because they sit behind a login, and one already
#: down before the window started. A tidy fixture of five 200s would
#: have passed three of the four broken versions.
#: The domain is `example.com` and not the one this was found on: the
#: artifact is for anybody, and check 117 is right to refuse a product
#: that carries the login of whoever happens to be building it.
BEFORE = {"https://uno.example.com/": 302,
          "https://dos.example.com/": 200,
          "https://tres.example.com/": 200,
          "https://cuatro.example.com/": None,
          "https://cinco.example.com/": 302}
BEHIND_PAGE = {u: 503 for u in BEFORE}

driven = 0

# ── 1: it waits before the FIRST look ────────────────────────────────
slept, calls = [], {"n": 0}


def look_flips_on_third():
    calls["n"] += 1
    return dict(BEFORE) if calls["n"] < 3 else dict(BEHIND_PAGE)


r = win.effect_of_page(BEFORE, look_flips_on_third, interval=5,
                       sleep=lambda s: slept.append(s))
driven += 1
if r.get("efecto") is not True:
    findings.append(f"a page whose effect appears on the third look was reported as "
                    f"{r.get('efecto')!r}: the edge takes a moment, and a window that "
                    f"asks once stops for a reason that is not true")
if not slept:
    findings.append("nothing waited at all: the URLs were asked the instant the hook "
                    "returned, before the edge could have picked the change up")
elif calls["n"] != len(slept):
    findings.append(f"it waited {len(slept)} time(s) for {calls['n']} look(s): the wait "
                    f"belongs BEFORE each look, including the first")

# ── 2: a page that changes nothing is False, after looking more than
#       once ──────────────────────────────────────────────────────────
calls2 = {"n": 0}


def look_never_changes():
    calls2["n"] += 1
    return dict(BEFORE)


r2 = win.effect_of_page(BEFORE, look_never_changes, interval=0, sleep=lambda s: None)
driven += 1
if r2.get("efecto") is not False:
    findings.append(f"a page that changed nothing came back {r2.get('efecto')!r}: the "
                    f"window would take the sites off the air behind a page nobody sees")
if calls2["n"] < 2:
    findings.append(f"it gave up after {calls2['n']} look(s): the edge is not instant, "
                    f"and «no effect» is the answer that stops a window")
if not r2.get("por_que"):
    findings.append("«no effect» comes back with no reason attached")

# ── 3: the shapes the round could not tell apart ─────────────────────
# One site already down, and the page takes the rest: the number is the
# whole difference, and the round's keys flatten numbers.
worse = {**BEFORE, "https://dos.example.com/": 503,
         "https://tres.example.com/": 503}
r3 = win.effect_of_page(BEFORE, lambda: worse, interval=0, sleep=lambda s: None)
driven += 1
if r3.get("efecto") is not True:
    findings.append("a page that took two more sites off the air, on an instance where "
                    "one was already down, was not seen: that is the exact shape the "
                    "round's flattened keys could not tell apart")

# A site that stops answering AT ALL is a change too, not an absence.
r4 = win.effect_of_page(BEFORE, lambda: {**BEFORE, "https://dos.example.com/": None},
                        interval=0, sleep=lambda s: None)
driven += 1
if r4.get("efecto") is not True:
    findings.append("a site that stopped answering at all was not counted as a change")

# And a site that RECOVERS is a change: the comparison is «something
# moved», not «everything got worse».
r5 = win.effect_of_page(BEFORE, lambda: {**BEFORE, "https://cuatro.example.com/": 200},
                        interval=0, sleep=lambda s: None)
driven += 1
if r5.get("efecto") is not True:
    findings.append("a site whose answer changed in the other direction was not counted: "
                    "the demand is that something moved, which is the weakest true "
                    "statement and therefore the right one")

# ── 4: no site at all is «cannot be read», never «no effect» ─────────
r6 = win.effect_of_page({}, lambda: {}, interval=0, sleep=lambda s: None)
driven += 1
if r6.get("efecto") is not None:
    findings.append(f"an instance that publishes no site came back {r6.get('efecto')!r}: "
                    f"there is nothing for a page to take off the air, and that is not "
                    f"the same as a page that did nothing")

# ── 5: the URLs come from the contracts ──────────────────────────────
import shutil
import tempfile
import pathlib as _pl

tmp = _pl.Path(tempfile.mkdtemp(prefix="aegis-218-"))
try:
    (tmp / "orgs").mkdir()
    (tmp / "orgs" / "uno.yaml").write_text("# a contract\ndominio: uno.example.com\n",
                                           encoding="utf-8")
    (tmp / "orgs" / "dos.yaml").write_text("tipo: estatico\n", encoding="utf-8")
    got = win.public_urls(tmp)
    driven += 1
    if got != ["https://uno.example.com/"]:
        findings.append(f"the public URLs were read as {got!r} from a tree with one "
                        f"contract that declares a domain and one that does not")
    if win.public_urls(tmp / "nada") != []:
        findings.append("a tree with no contracts came back with URLs")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# ── and the photo carries them, so the comparison is against the world
#     the window photographed ──────────────────────────────────────────
wsrc = open(os.path.join(ROOT, "lib", "aegis", "window.py"), encoding="utf-8").read()
code = "\n".join(ln for ln in wsrc.splitlines() if not ln.lstrip().startswith("#"))
if 'doc["sitios"]' not in code:
    findings.append("the photo does not record what the public sites answered: the page "
                    "would be compared against a world measured after the hook ran, which "
                    "is not a before")

for f in findings:
    print(f)
print(f"SCOPE: {driven} reading(s) driven with an injected clock and an injected lookup, "
      f"over the five sites of the instance that found this")
