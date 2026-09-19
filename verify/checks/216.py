"""Check 216 — «I could not look» is one answer and the others are not it.

THE MISTAKE THIS EXISTS TO PREVENT, WITH A DATE ON IT. Until 2026-09-18
`aegis update` had four answers, and the fourth —«no medible»— was
carrying three different things: an image this instance builds (nobody
to ask), a tag scheme nobody can order (asked, answered, unorderable),
and a registry that timed out (the instrument did not reach). The first
two never change and the third usually clears on the next run. Flattened
together they made `inventory` exit 2 every day on a healthy instance,
and the console say «something could not be looked at» on every page.

A verdict that never changes is a verdict nobody reads. That is the same
disease this whole command was written to treat, one level up, and this
is the check that keeps it split.

Five properties, driven rather than grepped:

  1. every state `upstream` can produce is one the vocabulary declares;
  2. the three groups PARTITION it: measured, behind/gone, and the one
     that means the instrument failed;
  3. `inventory` turns exactly one of them into `not-evaluable`;
  4. the console has a word for every one — a state with no word reaches
     the screen as the raw machine word;
  5. the cache is versioned, so a renamed state is not read back for six
     hours as the thing it used to mean.
"""
import json
import os
import re
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "lib"))
os.environ["AEGIS_ROOT"] = ROOT
findings = []

try:
    from aegis import screens, upstream
except Exception as e:                                    # noqa: BLE001
    print(f"the vocabulary cannot be imported ({e}): the answers were not compared")
    print("SCOPE: nothing was compared")
    sys.exit(0)

UPD = os.path.join(ROOT, "libexec", "aegis-update")
if not os.path.isfile(UPD):
    print("SCOPE: there is no aegis update")
    sys.exit(0)

# ── 1: every state the module can produce is declared ────────────────
# Read off the module's own source, because a state is a literal at a
# `return Answer(...)` and there is no way to enumerate them at runtime
# without calling the network.
src = open(os.path.join(ROOT, "lib", "aegis", "upstream.py"), encoding="utf-8").read()
# EVERYWHERE AN ANSWER IS BUILT, not only inside the module that defines
# the words. `SIN_ARRIBA` is returned by `aegis update` itself —the
# command is what knows an image is built here— and a scan of the module
# alone reported it as a state nothing can produce. The answer to «who
# may build one of these» is «anyone who imports it», so that is what
# gets read.
sources = [src]
for f in sorted(pathlib.Path(ROOT, "lib", "aegis").glob("*.py")):
    sources.append(f.read_text(encoding="utf-8"))
for f in sorted(pathlib.Path(ROOT, "libexec").iterdir()):
    if f.is_file():
        try:
            sources.append(f.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError):
            continue
produced = set()
for text in sources:
    code = "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith("#"))
    produced |= set(re.findall(r"Answer\(\s*(?:upstream\.)?([A-Z_]+)", code))
declared = {n for n in dir(upstream)
            if n.isupper() and isinstance(getattr(upstream, n), str)
            and getattr(upstream, n) in (
                "al-dia", "atrasado", "desaparecido", "sin-arriba", "sin-orden",
                "no-medible")}
for name in sorted(produced - declared):
    findings.append(f"upstream returns Answer({name}) and {name} is not one of the "
                    f"declared states: a consumer that switches on the word would fall "
                    f"through to whatever its default is")
unused = declared - produced
if unused:
    findings.append(f"declared and never produced: {sorted(unused)} — a state nothing "
                    f"can return is a branch every consumer carries for nothing")

# ── 2: the groups partition the vocabulary ───────────────────────────
every = {getattr(upstream, n) for n in declared}
measured = set(getattr(upstream, "MEASURED", ()))
unactionable = set(getattr(upstream, "UNACTIONABLE", ()))
moving = {upstream.ATRASADO, upstream.DESAPARECIDO}
blind = {upstream.NO_MEDIBLE}
if not measured:
    findings.append("upstream declares no MEASURED group: nothing says which answers mean "
                    "«this was measured», and every consumer has to guess")
overlap = measured & blind
if overlap:
    findings.append(f"{sorted(overlap)} is both measured and unmeasurable: the one "
                    f"distinction this vocabulary exists for")
missing = every - measured - moving - blind
if missing:
    findings.append(f"{sorted(missing)} belongs to no group: a consumer reading the groups "
                    f"would not see it at all")
if not unactionable <= measured:
    findings.append(f"UNACTIONABLE is not a subset of MEASURED: {sorted(unactionable - measured)} "
                    f"would be reported as something nobody could look at")
if upstream.NO_MEDIBLE in unactionable:
    findings.append("«nobody could ask» is listed as unactionable: it is not a permanent "
                    "property of the pin, it is a measurement that failed and usually "
                    "clears by itself")

# ── 3: exactly one of them becomes `not-evaluable` ───────────────────
upd = open(UPD, encoding="utf-8").read()
upd_code = "\n".join(ln for ln in upd.splitlines() if not ln.lstrip().startswith("#"))
m = re.search(r"if a\.state == upstream\.DESAPARECIDO:(.*?)\n            else:",
              upd_code, re.S)
if not m:
    findings.append("the inventory's mapping from an upstream answer to a house state "
                    "could not be read: the one join that decides the exit code")
else:
    turned = set(re.findall(r"a\.state == upstream\.([A-Z_]+)", m.group(0)))
    blind_branch = re.search(r"a\.state == upstream\.([A-Z_]+):\s*\n[^\n]*\n?\s*"
                             r"(?:#[^\n]*\n\s*)*steps\.not_evaluable", m.group(0))
    if not blind_branch:
        findings.append("no answer at all becomes `not-evaluable` in the inventory: a "
                        "measurement that failed would be reported as a measurement")
    elif blind_branch.group(1) != "NO_MEDIBLE":
        findings.append(f"the inventory turns {blind_branch.group(1)} into "
                        f"`not-evaluable`, and that is not the answer that means the "
                        f"instrument failed")

# ── the mapping, driven: a healthy tree must not exit 2 ──────────────
tmp = tempfile.mkdtemp(prefix="aegis-216-")
try:
    env = {**os.environ, "AEGIS_ROOT": ROOT,
           "PLATFORM_DIR": os.path.join(ROOT, "seed", "platform"),
           "AEGIS_HOME": tmp, "AEGIS_CMD": "aegis"}
    r = subprocess.run([sys.executable, UPD, "inventory", "--offline", "--json"],
                       capture_output=True, text=True, env=env, timeout=300)
    try:
        doc = json.loads(r.stdout)
    except ValueError:
        doc = None
        findings.append(f"`inventory --offline --json` returned no document (rc "
                        f"{r.returncode}): {(r.stderr or '')[-200:]}")
    if doc is not None:
        # --offline is the one case where EVERY pin is genuinely
        # unmeasurable, and the command has to say so: rc 2, and not one
        # step calling it `already`. If this comes back 0, the split has
        # been made in the wrong direction and a real outage would read
        # as a clean bill of health.
        if doc.get("rc") != 2:
            findings.append(f"with nothing asked upstream, `inventory` exited "
                            f"{doc.get('rc')} instead of 2: «I could not look» has been "
                            f"folded into an answer")
        states = {st.get("state") for st in doc.get("steps", [])
                  if st.get("step", "").startswith("pin:")}
        if states and states != {"not-evaluable"}:
            findings.append(f"with nothing asked upstream, some pins came back as "
                            f"{sorted(states - {'not-evaluable'})}: a state that was "
                            f"never measured")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# ── the first question is whether there is a question, driven ────────
# «Is there anybody to ask about this pin» is the decision that got
# folded into «I could not look», and it is the one worth driving
# rather than reading. A pin naming this instance's own registry and a
# pin of the class measured against the machine both have a complete
# answer, and neither of them is a failure to measure.
try:
    from aegis import pins as _pins

    own = _pins.Pin("jenkinsfile",
                    f"{upstream.OWN_REGISTRY}:5000/aegis-ci-node", "1.0", [("x", 1)])
    a = upstream.for_pin(own)
    if a.state != upstream.SIN_ARRIBA:
        findings.append(f"an image this instance BUILDS comes back {a.state!r}: there is "
                        f"nobody to ask about it, and that is an answer rather than a "
                        f"measurement that failed")
    if a.state not in measured:
        findings.append("the answer about an image this instance builds is not in the "
                        "measured group: `inventory` would exit 2 about a pin nothing "
                        "is wrong with")
    machine = _pins.Pin("apt", "jq", None, [("x", 1)])
    b = upstream.for_pin(machine)
    if b.state != upstream.SIN_ARRIBA:
        findings.append(f"a pin measured against the machine comes back {b.state!r} "
                        f"instead of «there is nobody upstream to ask»")
    if not (a.why and b.why):
        findings.append("an answer that nobody can act on comes back with no reason: the "
                        "whole difference from «I could not look» is that this one knows "
                        "why")
except Exception as e:                                    # noqa: BLE001
    findings.append(f"the question «is there anybody to ask» could not be driven ({e})")

# ── 4: the console has a word for every state ────────────────────────
words = getattr(screens, "UPSTREAM_WORD", {}) or {}
for state in sorted(every):
    if state not in words:
        findings.append(f"the console has no word for {state!r}: it would reach the "
                        f"screen as the machine's own spelling, which is the one thing "
                        f"the console is for translating")
for state in sorted(set(words) - every):
    findings.append(f"the console translates {state!r} and nothing produces it")
if any(isinstance(v, tuple) for v in words.values()):
    findings.append("a word in the console's table carries a state beside it: the states "
                    "on that page come from the documents, and a table that assigns one "
                    "is how a screen invents (I-1)")

# ── 5: the cache is versioned ────────────────────────────────────────
if not hasattr(upstream, "CACHE_VOCABULARY"):
    findings.append("the cache carries no vocabulary version: the day a state is renamed, "
                    "six hours of cached answers keep being read back as the thing the "
                    "word used to mean")
else:
    cache_src = re.search(r"def load_cache\(.*?\n\n", src, re.S)
    if cache_src and "CACHE_VOCABULARY" not in cache_src.group(0):
        findings.append("the cache declares a vocabulary version and does not check it on "
                        "the way in: a version nobody reads is a comment")

for f in findings:
    print(f)
print(f"SCOPE: {len(every)} answer(s) across the module, the inventory's mapping, the "
      f"console's words and the cache's version")
