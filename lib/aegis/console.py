"""The console's renderer: documents in, HTML out.

WHY IT IS A PURE FUNCTION. `render()` does no I/O, talks to nothing and
knows no clock. That is what lets the whole console be built and proved
before a single byte is served: check 122 renders every case of
console/cases/ and reads the result back, with no cluster, no browser
and no npm. The server, when it comes, is a thin thing that fetches
documents and hands them here.

WHAT IT PROMISES, and what check 122 holds it to:

  I-1  no state is lost and none is invented. Every distinct state the
       documents carry reaches the screen; every state on the screen
       comes from the documents.
  I-2  the verdict is never kinder than its readings. If something could
       not be evaluated — or gave back no document at all — the page
       does not say everything is fine.

THE STATE TRAVELS IN AN ATTRIBUTE, not in a word. `data-state` is the
contract: the words on the screen are for people and may be translated,
reworded or shortened without any check noticing, which is exactly as
it should be. What may never change quietly is which state a thing IS.
"""
import html as _html
import json
import os

# ── the vocabulary of the screen ─────────────────────────────────────
# Four states, and the fourth is the reason the product exists. `busy`
# is declared and unused on purpose: the round has no way yet to say «I
# am working on it», and the day it does, the word is already here
# instead of being invented under pressure.
FINE, WRONG, ATTENTION, UNSEEN, BUSY = "fine", "wrong", "attention", "unseen", "busy"

# Was it looked at? UNSEEN is the only no, and that single fact is what
# stops the flattening: check 122 reads this table to decide whether a
# translation lies.
LOOKED_AT = {FINE: True, WRONG: True, ATTENTION: True, BUSY: True, UNSEEN: False}
# Does it mean nothing is being asked of anybody?
IS_FINE = {FINE: True, WRONG: False, ATTENTION: False, BUSY: False, UNSEEN: False}

# The producers' words -> the screen's. It has to be TOTAL: a word with
# no translation is a state the screen cannot show, and check 122 goes
# red the day a producer learns a new one.
SCREEN = {
    # the four of the house (lib/aegis/outcomes.py)
    "done": FINE, "already": FINE, "wrong": WRONG, "not-evaluable": UNSEEN,
    # the round's own, which its measures carry (libexec/aegis-check)
    "good": FINE, "bad": WRONG, "notice": ATTENTION, "not-evaluated": UNSEEN,
}

# Worst first: the order in which a verdict is decided, and the order in
# which things are shown. UNSEEN outranks WRONG on purpose — a thing
# known to be broken is better news than a thing nobody could look at.
SEVERITY = [UNSEEN, WRONG, ATTENTION, BUSY, FINE]


def worst(states):
    for s in SEVERITY:
        if s in states:
            return s
    return FINE


# ── reading a case ───────────────────────────────────────────────────
# The only I/O in this module, and it is here rather than in the check
# so that the server and the suite load a case exactly the same way.
def readings_of_case(directory):
    import yaml
    case = yaml.safe_load(open(os.path.join(directory, "case.yaml"), encoding="utf-8")) or {}
    readings = []
    for entry in case.get("producido_por") or []:
        reading = {"comando": entry.get("comando", "?"), "rc": entry.get("rc"),
                   "documento": None, "sin_documento": entry.get("sin_documento")}
        name = entry.get("documento")
        if name:
            path = os.path.join(directory, "documents", name)
            with open(path, encoding="utf-8") as fh:
                reading["documento"] = json.load(fh)
        readings.append(reading)
    return readings


# ── the drawing ──────────────────────────────────────────────────────
def _e(text):
    return _html.escape(str(text), quote=True)


def _chip(state, label):
    return f'<span class="chip" data-state="{state}">{_e(label)}</span>'


def _measure(measure):
    state = SCREEN.get(measure.get("state"), UNSEEN)
    notes = "".join(f'<p class="note">{_e(n)}</p>' for n in measure.get("notes") or [])
    return (f'<li class="measure" data-state="{state}">'
            f'{_chip(state, measure.get("state", "?"))}'
            f'<span class="what">{_e(measure.get("measure", ""))}</span>{notes}</li>')


def _step(step):
    state = SCREEN.get(step.get("state"), UNSEEN)
    measures = step.get("measures") or []
    inner = f'<ul class="measures">{"".join(_measure(m) for m in measures)}</ul>' if measures else ""
    # Everything that is not `step`, `state` or `measures` is DATA the
    # producer chose to attach, and it is shown rather than dropped: it
    # is how a surplus CNAME reaches the screen without inventing a
    # state for it.
    extra = {k: v for k, v in step.items()
             if k not in ("step", "state", "measures", "notes", "counts")}
    facts = "".join(f'<dt>{_e(k)}</dt><dd>{_e(v)}</dd>' for k, v in extra.items())
    facts = f'<dl class="facts">{facts}</dl>' if facts else ""
    return (f'<article class="step" data-state="{state}" data-step="{_e(step.get("step", "?"))}">'
            f'<h3>{_e(step.get("step", "?"))}</h3>{_chip(state, step.get("state", "?"))}'
            f'{facts}{inner}</article>')


def _blind(reading):
    """A command that gave back no document. THE CASE ZERO.

    Most dashboards answer this with a spinner that never stops, which
    is lying politely: the page does not say «I do not know», it says
    «wait», and that is a promise it will not keep. Here it is a state
    with its own name, and the reason travels with it.
    """
    return (f'<section class="source" data-state="{UNSEEN}" '
            f'data-command="{_e(reading["comando"])}">'
            f'<h2>{_e(reading["comando"])}</h2>{_chip(UNSEEN, "could not look")}'
            f'<p class="why">{_e(reading["sin_documento"])}</p></section>')


def _source(reading):
    if reading.get("sin_documento") or reading.get("documento") is None:
        return _blind(reading), {UNSEEN}
    doc = reading["documento"]
    steps = doc.get("steps") or []
    states = set()
    body = []
    for step in steps:
        states.add(SCREEN.get(step.get("state"), UNSEEN))
        for m in step.get("measures") or []:
            states.add(SCREEN.get(m.get("state"), UNSEEN))
        body.append(_step(step))
    if not steps:
        # Zero steps is not success: outcomes.py says so in its own rc.
        states.add(UNSEEN)
        body.append(f'<p class="empty" data-state="{UNSEEN}">'
                    f'nothing was measured</p>')
    state = worst(states)
    return (f'<section class="source" data-state="{state}" '
            f'data-command="{_e(reading["comando"])}" data-rc="{_e(reading.get("rc"))}">'
            f'<h2>{_e(reading["comando"])}</h2>{_chip(state, state)}'
            f'{"".join(body)}</section>'), states


def verdict_of(readings):
    """How the whole thing is. Never kinder than its readings (I-2)."""
    states = set()
    for r in readings:
        if r.get("sin_documento") or r.get("documento") is None or r.get("rc") == 2:
            states.add(UNSEEN)
        elif r.get("rc") == 1:
            states.add(WRONG)
        for step in (r.get("documento") or {}).get("steps") or []:
            states.add(SCREEN.get(step.get("state"), UNSEEN))
            for m in step.get("measures") or []:
                states.add(SCREEN.get(m.get("state"), UNSEEN))
    return worst(states) if states else UNSEEN


# The one sentence at the top. It is the alarm: if a screen needs a
# colour to frighten somebody, the sentence is badly written.
SENTENCE = {
    FINE: "Everything is in order.",
    ATTENTION: "Something is asking for a decision.",
    WRONG: "Something is wrong.",
    UNSEEN: "Something could not be looked at.",
    BUSY: "aegis is working on it.",
}


def render(readings):
    bodies, _ = [], None
    for reading in readings:
        body, _ = _source(reading)
        bodies.append(body)
    v = verdict_of(readings)
    head = (f'<header class="verdict" data-state="{v}">'
            f'<p class="sentence">{_e(SENTENCE[v])}</p></header>')
    return (f'<main class="sereno" data-veredicto="{v}">{head}'
            f'{"".join(bodies)}</main>')

# ── the whole page ───────────────────────────────────────────────────
# SKIN = share/console/sereno.css, and it is INLINED rather than linked.
# One document, one request, no static path to get wrong and nothing
# fetched from anywhere: the console is served on loopback and the file
# is 6 KB. Reading it is the only I/O this module does besides loading a
# case, and it is kept out of render() so that the pure function stays
# pure and check 122 can keep calling it with no filesystem at all.
SKIN = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "share", "console", "sereno.css")


def skin():
    try:
        with open(SKIN, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        # A console with no skin still has to draw: the states travel in
        # the attributes, and the text is readable unstyled. Saying so
        # is better than serving a blank page.
        return "/* the skin could not be read; the states are in the data-state attributes */"


def page(readings, title="aegis"):
    return ("<!doctype html>\n"
            '<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{_e(title)}</title><style>{skin()}</style></head>"
            f"<body>{render(readings)}</body></html>\n")
