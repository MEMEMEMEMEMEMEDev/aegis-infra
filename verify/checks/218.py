"""Check 218 — the page is not judged before anybody could have seen it.

WITH A DATE ON IT: 2026-09-20, the first update window ever opened on a
real instance. The hook deployed the maintenance page in 5.5 seconds,
the window read the round at once, and answered «the hook ran and the
public sites still answer». The page was up. The tenant probes run
every thirty seconds and had not run again yet, so the round was
describing a world that no longer existed.

The window stopped, which was the right thing to do with a measurement
it could not trust — but the reason it printed was false, and a
protocol that stops for false reasons is one nobody lets run
unattended.

So the reading WAITS, and the wait comes from how often the probes
actually run rather than from a number somebody typed. Four properties,
all driven in milliseconds with an injected clock and an injected
reader:

  1. it waits before the FIRST read, not only between retries — the
     probe that matters is the one that has yet to run;
  2. a change that only shows up on a later reading is still seen;
  3. a page that genuinely does nothing comes back False, after having
     asked more than once;
  4. the interval is DERIVED from the platform's own config, and a
     config it cannot read is said out loud instead of guessed at
     quietly.
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

if not hasattr(win, "effect_of_page"):
    print("the window has no effect_of_page: whether the maintenance page did anything "
          "is decided somewhere that cannot be exercised without a cluster")
    print("SCOPE: nothing was driven")
    sys.exit(0)


def _round(state):
    return {"steps": [{"step": "observability",
                       "measures": [{"measure": "the N public site(s) answer their probe",
                                     "state": state}]}]}


UP, DOWN = _round("good"), _round("bad")

# ── 1 + 2: a change that only appears later is still seen ────────────
slept, calls = [], {"n": 0}


def read_flips_on_third():
    calls["n"] += 1
    return UP if calls["n"] < 3 else DOWN


r = win.effect_of_page(UP, read_flips_on_third, interval=30,
                       sleep=lambda s: slept.append(s))
if r.get("efecto") is not True:
    findings.append(f"a page whose effect shows up on the third reading was reported as "
                    f"{r.get('efecto')!r}: the window would stop for a reason that is not "
                    f"true, which is what happened on 2026-09-20")
if not slept:
    findings.append("nothing waited at all: the round was read the instant the hook "
                    "returned, and the probes had not run again")
elif calls["n"] != len(slept):
    findings.append(f"it waited {len(slept)} time(s) for {calls['n']} reading(s): the "
                    f"wait has to come BEFORE each read, including the first")
if slept and min(slept) < 30:
    findings.append(f"it waited {min(slept)}s for probes that run every 30s: shorter than "
                    f"one interval is no wait at all")

# ── 3: a page that does nothing is still a False, after asking twice ─
calls2 = {"n": 0}


def read_never_changes():
    calls2["n"] += 1
    return UP


r2 = win.effect_of_page(UP, read_never_changes, interval=1, sleep=lambda s: None)
if r2.get("efecto") is not False:
    findings.append(f"a page that changed nothing came back {r2.get('efecto')!r}: the "
                    f"window would take the sites off the air behind a page nobody sees")
if calls2["n"] < 2:
    findings.append(f"it gave up after {calls2['n']} reading(s): one probe cycle can be "
                    f"missed, and «no effect» is the answer that stops a window")
if not r2.get("por_que"):
    findings.append("«no effect» comes back with no reason attached")

# ── and a reader that cannot answer is «could not look», never False ─
def read_explodes():
    raise RuntimeError("the round could not be taken")


r3 = win.effect_of_page(UP, read_explodes, interval=1, sleep=lambda s: None)
if r3.get("efecto") is not None:
    findings.append(f"a round that could not be taken came back {r3.get('efecto')!r} "
                    f"instead of «nobody could look»")

# ── 4: the interval is derived, and an unreadable one says so ────────
if not hasattr(win, "probe_interval"):
    findings.append("nothing derives how often the probes run: the wait would be a "
                    "number typed here, and the day somebody moves the scrape interval "
                    "this would keep waiting the old one")
else:
    import tempfile
    import pathlib as _pl
    tmp = _pl.Path(tempfile.mkdtemp(prefix="aegis-218-"))
    d = tmp / "k8s" / "base" / "observability" / "vmagent"
    d.mkdir(parents=True)
    (d / "values.yaml").write_text("scrape:\n    scrape_interval: 45s\n", encoding="utf-8")
    got = win.probe_interval(tmp)
    if got != 45:
        findings.append(f"the probes' interval was read as {got!r} from a config that "
                        f"says 45s")
    if win.probe_interval(tmp / "nada") is not None:
        findings.append("a config that cannot be read came back as a number instead of "
                        "None: the caller could not tell a measurement from a guess")
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)

# ── and a guess is handed back AS a guess, not as a number ───────────
# Driven rather than grepped: the caller has to be able to tell the
# config's answer from a default, and a function that returns a bare
# number makes that impossible no matter how carefully the caller is
# written.
if not hasattr(win, "probe_interval_or_guess"):
    findings.append("nothing hands back the interval together with whether it was "
                    "measured: a silent default about WHEN to measure is how the first "
                    "window stopped for a reason that was not true")
else:
    import tempfile as _tf
    import pathlib as _pl2
    import shutil as _sh
    t2 = _pl2.Path(_tf.mkdtemp(prefix="aegis-218b-"))
    d2 = t2 / "k8s" / "base" / "observability" / "vmagent"
    d2.mkdir(parents=True)
    (d2 / "values.yaml").write_text("    scrape_interval: 45s\n", encoding="utf-8")
    val, note = win.probe_interval_or_guess(t2)
    if (val, note) != (45, None):
        findings.append(f"a readable config came back as {(val, note)!r}: a measured "
                        f"interval must arrive with no note, or every caller learns to "
                        f"ignore the note")
    val2, note2 = win.probe_interval_or_guess(t2 / "nada")
    if not note2:
        findings.append("an unreadable config came back with no note: the window would "
                        "wait on a guess and report it as a measurement")
    if not val2:
        findings.append("an unreadable config came back with no interval either: the "
                        "window would not wait at all")
    _sh.rmtree(t2, ignore_errors=True)

upd = open(os.path.join(ROOT, "libexec", "aegis-update"), encoding="utf-8").read()
code = "\n".join(ln for ln in upd.splitlines() if not ln.lstrip().startswith("#"))
if "probe_interval_or_guess" not in code:
    findings.append("the window does not ask for the interval together with whether it "
                    "was measured")

for f in findings:
    print(f)
print(f"SCOPE: 4 reading(s) driven with an injected clock ({len(slept)} wait(s) of "
      f"{slept[0] if slept else '-'}s), and the interval read from a config")
