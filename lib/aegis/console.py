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
    when = case.get("medido_en")
    for entry in case.get("producido_por") or []:
        reading = {"comando": entry.get("comando", "?"), "rc": entry.get("rc"),
                   "documento": None, "sin_documento": entry.get("sin_documento"),
                   # WHEN, and it travels with the reading rather than
                   # being taken from a clock at draw time: render() has
                   # no clock on purpose, and a measurement shown
                   # without its age is the oldest lie a dashboard
                   # tells — a number from forty minutes ago read as if
                   # it were now.
                   "medido_en": str(when) if when else None}
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


def _when(reading):
    w = reading.get("medido_en")
    return f' data-measured-at="{_e(w)}"' if w else ' data-measured-at="unknown"'


def _age(reading):
    """When this reading was taken, on the page and not only in an
    attribute. A console that shows a number without its age invites
    somebody to act on a measurement from forty minutes ago as if it
    were now — and unlike a wrong number, nothing about the screen
    looks off while they do it."""
    w = reading.get("medido_en")
    return (f'<p class="age">measured {_e(w)}</p>' if w
            else '<p class="age" data-state="unseen">nobody recorded when this was measured</p>')


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


# ── panels ───────────────────────────────────────────────────────────
# A panel KNOWS what a particular document means and draws it as the
# thing it is: organisations as organisations, traffic as traffic. The
# generic drawing below stays underneath all of them, and that is
# deliberate — a source nobody has written a panel for yet still gets
# rendered, step by step, with every state intact. Panels are an
# improvement over the fallback, never a replacement for it, so a new
# command cannot make its own reading disappear from the screen while
# somebody gets around to designing it.
#
# What a panel may NOT do is quiet a state. It may collapse what is
# FINE —that is rule 1: what needs attention rises, what is fine sinks—
# and nothing else. Check 122 renders every case and compares what the
# documents carry against what the screen shows, so a panel that
# swallows something goes red in the same run that wrote it.
def _bytes(n):
    n = float(n)
    for unit in ("B", "kB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def _num(n):
    return f"{int(n):,}".replace(",", "\u2009")   # thin space: 5 423


def _fact(label, value, mono=True):
    cls = "figure mono" if mono else "figure"
    return (f'<div class="fact"><span class="{cls}">{_e(value)}</span>'
            f'<span class="label">{_e(label)}</span></div>')


def _window(step):
    return f"last {step.get('hours', 24)}h"


def _panel_organizations(doc, states):
    tiles = []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "").split(":", 1)[-1]
        if not step.get("valid", True):
            tiles.append(
                f'<article class="tile" data-state="{state}">'
                f'<h3>{_e(name)}</h3>{_chip(state, "contract refused")}'
                f'<p class="why">{_e(step.get("error", ""))}</p></article>')
            continue
        services = step.get("servicios") or []
        chips = "".join(
            f'<span class="srv" data-kind="{_e(sv.get("tipo"))}">{_e(sv.get("nombre"))}'
            f'<i>{_e(sv.get("tipo"))}</i></span>' for sv in services)
        extras = []
        if step.get("bucket"):
            extras.append("bucket")
        if step.get("ai"):
            extras.append(f"ai {step['ai']}")
        tiles.append(
            f'<article class="tile" data-state="{state}">'
            f'<h3><a href="/org/{_e(name)}">{_e(name)}</a></h3>{_chip(state, "contract")}'
            f'<p class="host mono">{_e(step.get("dominio") or "no public domain")}</p>'
            f'<div class="srvs">{chips}</div>'
            f'<p class="meta">quota <b>{_e(step.get("cuota"))}</b>'
            + (f' · {_e(" · ".join(extras))}' if extras else "")
            + f' · {len(services)} service(s)</p></article>')
    if not tiles:
        states.add(UNSEEN)
        tiles.append(f'<p class="empty" data-state="{UNSEEN}">no contract was read</p>')
    return f'<div class="tiles">{"".join(tiles)}</div>'


def _panel_traffic(doc, states):
    rows, tail = [], []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "").split(":", 1)[-1]
        if name in ("platform", "unattributed", "total") or "requests" not in step:
            note = step.get("note")
            tail.append(f'<li data-state="{state}">{_chip(state, name)}'
                        f'<span class="mono">{_e(_num(step.get("requests", 0)))} req</span>'
                        + (f'<span class="note">{_e(note)}</span>' if note else "") + "</li>")
            continue
        errors = int(step.get("errors", 0))
        rows.append(
            f'<article class="tile" data-state="{state}">'
            f'<h3>{_e(name)}</h3>{_chip(state, _window(step))}'
            f'<div class="facts-row">'
            f'{_fact("requests", _num(step.get("requests", 0)))}'
            f'{_fact("5xx", _num(errors))}'
            f'{_fact("p95", str(step.get("p95_ms", 0)) + " ms")}'
            f'{_fact("served", _bytes(step.get("bytes", 0)))}'
            f'</div></article>')
    if not rows:
        states.add(UNSEEN)
        rows.append(f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>')
    return (f'<div class="tiles">{"".join(rows)}</div>'
            + (f'<ul class="tail">{"".join(tail)}</ul>' if tail else ""))


def _panel_round(doc, states):
    cells = []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        # Rule 1, mechanically: a section that is fine is a dot and a
        # name. A section that is not opens itself, with only the
        # measures that are not fine — and the fine ones are COUNTED so
        # that the collapse never reads as «there was nothing else».
        shown, hidden = [], 0
        for m in step.get("measures") or []:
            ms = SCREEN.get(m.get("state"), UNSEEN)
            states.add(ms)
            if ms == FINE and state != FINE:
                hidden += 1
                continue
            if state == FINE:
                hidden += 1
                continue
            notes = "".join(f'<p class="note">{_e(n)}</p>' for n in m.get("notes") or [])
            shown.append(f'<li class="measure" data-state="{ms}">{_chip(ms, ms)}'
                         f'<span class="what">{_e(m.get("measure", ""))}</span>{notes}</li>')
        body = ""
        if shown:
            body = f'<ul class="measures">{"".join(shown)}</ul>'
        if hidden:
            body += f'<p class="rest">{hidden} more, all fine</p>'
        cells.append(
            f'<article class="cell" data-state="{state}" data-step="{_e(step.get("step",""))}">'
            f'{_chip(state, state)}<h3>{_e(step.get("step", "?"))}</h3>{body}</article>')
    if not cells:
        states.add(UNSEEN)
        cells.append(f'<p class="empty" data-state="{UNSEEN}">the round measured nothing</p>')
    return f'<div class="grid">{"".join(cells)}</div>'


def _panel_edge(doc, states):
    good, bad_ = [], []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "")
        if name.startswith("hostname:"):
            bad_.append(f'<li data-state="{state}">{_chip(state, "missing")}'
                        f'<span class="mono">{_e(name.split(":", 1)[1])}</span></li>')
        elif name == "surplus-cnames":
            hosts = step.get("hostnames") or []
            good.append(f'<li data-state="{state}">{_chip(state, "surplus")}'
                        f'<span class="mono">{_e(", ".join(hosts))}</span>'
                        f'<span class="note">no contract asks for these; they do not move the rc</span></li>')
        else:
            good.append(f'<li data-state="{state}">{_chip(state, "at the edge")}'
                        f'<span class="mono">{_e(step.get("hostnames", "?"))} hostname(s) exist</span></li>')
    return f'<ul class="tail">{"".join(bad_ + good)}</ul>'


def _panel_capacity(doc, states):
    figures, fits = [], []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "")
        if name.startswith("fits:"):
            plan = name.split(":", 1)[1]
            room = step.get("room")
            # «none» and «unknown» are different words on purpose: one is
            # a measurement, the other is the absence of one, and this is
            # the panel where confusing them costs an organization.
            answer = ("unknown" if room is None
                      else f"{room} more" if room else "none")
            fits.append(
                f'<li data-state="{state}">{_chip(state, plan)}'
                f'<span class="mono">{_e(answer)}</span>'
                + (f'<span class="note">{_e(step["binding"])} is what runs out first</span>'
                   if step.get("binding") else "") + "</li>")
        elif name in ("capacity:memory", "capacity:cpu"):
            figures.append(_fact(name.split(":", 1)[1] + " free",
                                 step.get("free_human", "?")))
        elif name == "capacity:nodes":
            figures.append(_fact("pods asking", _num(step.get("pods", 0))))
        else:
            figures.append(_fact(name.split(":", 1)[-1], step.get("why", "not measured")))
    head = (f'<article class="tile" data-state="{worst(states)}">'
            f'<div class="facts-row">{"".join(figures)}</div></article>'
            if figures else "")
    return f'<div class="tiles">{head}</div>' + (f'<ul class="tail">{"".join(fits)}</ul>' if fits else "")


def _panel_builds(doc, states):
    rows = []
    gaps = []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "")
        if name == "builds" and step.get("links_elsewhere"):
            # The gaps come as DATA on the summary step (see the comment
            # in aegis-builds about the permanent rc 2). They are drawn
            # as unmeasured all the same: on a chain, a link that is
            # simply absent reads as fine.
            for link, who in (step["links_elsewhere"] or {}).items():
                states.add(UNSEEN)
                gaps.append(f'<li data-state="{UNSEEN}">{_chip(UNSEEN, link)}'
                            f'<span class="note">not measured here — {_e(who)}</span></li>')
            continue
        links = step.get("links") or {}
        # THE CHAIN. Each link carries its own state, so a link nobody
        # measured is drawn as unmeasured and not as a gap in a row of
        # ticks — which on a chain reads as «fine».
        drawn = "".join(
            f'<span class="link" data-state="{SCREEN.get(v, UNSEEN)}" '
            f'title="{_e(k)}">{_e(k)}</span>'
            for k, v in links.items())
        for v in links.values():
            states.add(SCREEN.get(v, UNSEEN))
        rows.append(
            f'<article class="build" data-state="{state}">'
            f'<h3>{_e(step.get("image", "?"))}</h3>'
            f'<span class="mono build-n">build {_e(step.get("build", "?"))}</span>'
            f'<div class="chain">{drawn}</div>'
            + (f'<p class="note">{_e(step["why"])}</p>' if step.get("why") else "")
            + '</article>')
    if not rows:
        states.add(UNSEEN)
        rows.append(f'<p class="empty" data-state="{UNSEEN}">no build was read</p>')
    return (f'<div class="builds">{"".join(rows)}</div>'
            + (f'<ul class="tail">{"".join(gaps)}</ul>' if gaps else ""))



def _bar(pct, state):
    """One dimension of a quota, drawn. The number is beside it: a bar
    on its own is a feeling, and the decision («can I add a service»)
    is taken on the figure."""
    width = max(0, min(100, pct))
    return (f'<div class="bar" data-state="{state}">'
            f'<span style="width:{width:.0f}%"></span></div>')


def _panel_tenant(doc, states):
    """One organization: what its contract declares, against what is
    running. The tiles are the services; everything the contract does
    NOT declare is drawn apart and never folded in, because an
    unclaimed workload or an unclaimed volume is precisely the thing
    that has been invisible until now."""
    tiles, extra, head = [], [], []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "")
        kind, _, what = name.partition(":")

        if kind == "namespace":
            head.append(f'<div class="fact"><span class="figure mono">'
                        f'{_e(step.get("namespace", "?"))}</span>'
                        f'<span class="label">namespace</span></div>')
            if not step.get("exists"):
                extra.append(f'<li data-state="{state}">{_chip(state, "namespace")}'
                             f'<span class="note">the contract is in git and '
                             f'nothing of it is running</span></li>')
            continue

        if kind == "service":
            ready, desired = step.get("ready"), step.get("desired")
            count = (f'{ready}/{desired}' if desired is not None else "none")
            bits = [f'<span class="srv">{_e(step.get("tipo", "?"))}</span>']
            if step.get("publico"):
                bits.append(f'<span class="srv mono">{_e(step["publico"])}</span>')
            if step.get("volume"):
                bits.append(f'<span class="srv">{_e(step.get("volume_size") or "disk")}'
                            f'<i>{_e(step.get("volume_phase", ""))}</i></span>')
            elif step.get("volume_phase") == "missing":
                bits.append('<span class="srv" data-state="wrong">no volume</span>')
            elif step.get("volume_unmeasured"):
                bits.append(f'<span class="srv" data-state="unseen">disk not measured</span>')
            why = step.get("why")
            tiles.append(
                f'<article class="tile" data-state="{state}">'
                f'<h3>{_e(what)}</h3>{_chip(state, count)}'
                f'<div class="srvs">{"".join(bits)}</div>'
                + (f'<p class="why">{_e(_WHY.get(why, why))}</p>' if why else "")
                + (f'<p class="host mono">{_e(step["digest"][:19])}\u2026</p>'
                   if step.get("digest") else "")
                + '</article>')
            continue

        if kind == "public":
            eps = step.get("endpoints")
            note = ("not routed" if not step.get("routed") else
                    "routed at nobody" if eps == 0 else
                    "nobody counted who is behind it" if eps is None else
                    f'{eps} behind it')
            extra.append(f'<li data-state="{state}">{_chip(state, step.get("publico", "/"))}'
                         f'<span class="mono">{_e(step.get("service", ""))}</span>'
                         f'<span class="note">{_e(note)}</span></li>')
            continue

        if kind == "routing":
            for host in step.get("hosts") or []:
                head.append(f'<div class="fact"><span class="figure mono">{_e(host)}</span>'
                            f'<span class="label">host</span></div>')
            continue

        if kind == "quota":
            pct = step.get("percent")
            if pct is None:
                extra.append(f'<li data-state="{state}">{_chip(state, "quota")}'
                             f'<span class="note">{_e(step.get("why", "not measured"))}'
                             f'</span></li>')
                continue
            tight = step.get("tightest", "")
            used = (step.get("used") or {}).get(tight)
            hard = (step.get("hard") or {}).get(tight)
            head.append(
                f'<div class="fact quota"><span class="figure">{pct:.0f}%</span>'
                f'<span class="label">{_e(tight)}</span>'
                f'{_bar(pct, state)}'
                f'<span class="label mono">{_e(used)} of {_e(hard)}</span></div>')
            continue

        # unclaimed:<workload> and unclaimed-volume:<claim>, and
        # anything a future version of the command learns to say. The
        # default is to DRAW IT, never to drop it: a step this panel
        # does not recognise is still a measurement, and the one thing
        # the console may not do is lose one.
        extra.append(
            f'<li data-state="{state}">{_chip(state, kind)}'
            f'<span class="mono">{_e(what)}</span>'
            f'<span class="note">{_e(_WHY.get(kind, kind))}</span></li>')

    if not tiles and not extra:
        states.add(UNSEEN)
        return f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>'
    return ((f'<div class="facts-row head">{"".join(head)}</div>' if head else "")
            + (f'<div class="tiles">{"".join(tiles)}</div>' if tiles else "")
            + (f'<ul class="tail">{"".join(extra)}</ul>' if extra else ""))


# The sentences the panel puts beside a machine word. They live here and
# not in the command because they are for a person reading a screen; the
# command's word is what travels, and check 123 makes sure the screen
# never has to READ one of these back.
_WHY = {
    "no-workload": "declared in the contract, and nothing in the cluster answers to it",
    "no-namespace": "the namespace does not exist",
    "unclaimed": "running here, and no service of the contract claims it",
    "unclaimed-volume": "bound here, and no service of the contract declares it \u2014 "
                        "so nothing copies it",
}


def _panel_backup(doc, states):
    cards = []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        org = step.get("step", "").split(":", 1)[-1]
        age = step.get("age_hours")
        cad = step.get("cadence_seconds") or 0
        facts = []
        if age is not None:
            facts.append(_fact("hours old", f"{age:g}"))
        if cad:
            facts.append(_fact("every", f"{cad // 3600}h"))
        facts.append(_fact("copies", str(step.get("copies", 0))))
        if step.get("bytes"):
            facts.append(_fact("stored", _bytes(step["bytes"])))
        note = step.get("note") or _WHY_BACKUP.get(step.get("why"), step.get("why"))
        if step.get("late"):
            note = "later than two turns of its own clock"
        cards.append(
            f'<article class="tile" data-state="{state}">'
            f'<h3>{_e(org)}</h3>{_chip(state, "off-site copy")}'
            f'<div class="facts-row">{"".join(facts)}</div>'
            + (f'<p class="why">{_e(note)}</p>' if note else "") + '</article>')
    if not cards:
        states.add(UNSEEN)
        return f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>'
    return f'<div class="tiles">{"".join(cards)}</div>'


_WHY_BACKUP = {
    "no-copy-at-the-destination": "this organization holds state and there is no copy "
                                  "of it at the destination",
    "destination-unreachable": "the destination did not answer \u2014 which is not the "
                               "same as having no copy",
    "no-readable-date": "there are objects there and none of them has a readable date: "
                        "their age cannot be stated",
}


PANELS = {
    "org list": _panel_organizations,
    "traffic show": _panel_traffic,
    "check": _panel_round,
    "edge check": _panel_edge,
    "capacity show": _panel_capacity,
    "builds show": _panel_builds,
    # Parameterised: the command carries the organization's name, so the
    # panel is found by the longest key that starts the command.
    "tenant show": _panel_tenant,
    "data remote status": _panel_backup,
}


def panel_for(command):
    """The panel for a command, by the longest declared prefix. A
    command with no panel is not an error: `_source` falls back to the
    generic dump, which shows every step and loses nothing. A panel is
    an improvement over that, never a replacement for it."""
    best = None
    for key in PANELS:
        if command == key or command.startswith(key + " "):
            if best is None or len(key) > len(best):
                best = key
    return PANELS[best] if best else None


def _blind(reading):
    """A command that gave back no document. THE CASE ZERO.

    Most dashboards answer this with a spinner that never stops, which
    is lying politely: the page does not say «I do not know», it says
    «wait», and that is a promise it will not keep. Here it is a state
    with its own name, and the reason travels with it.
    """
    return (f'<section class="source" data-state="{UNSEEN}" '
            f'data-command="{_e(reading["comando"])}"{_when(reading)}>'
            f'<h2>{_e(reading["comando"])}</h2>{_chip(UNSEEN, "could not look")}'
            f'<p class="why">{_e(reading["sin_documento"])}</p>'
            f'{_age(reading)}</section>')


def _source(reading):
    if reading.get("sin_documento") or reading.get("documento") is None:
        return _blind(reading), {UNSEEN}
    doc = reading["documento"]
    steps = doc.get("steps") or []
    states = set()
    panel = panel_for(reading.get("comando") or "")
    if panel and steps:
        body = [panel(doc, states)]
    else:
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
            f'data-command="{_e(reading["comando"])}" data-rc="{_e(reading.get("rc"))}"'
            f'{_when(reading)}>'
            f'<h2>{_e(reading["comando"])}</h2>{_chip(state, state)}'
            f'{_age(reading)}{"".join(body)}</section>'), states


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


def render(readings, subject=None):
    """The page's body. `subject` names WHO this page is about — an
    organization — and when it is given the verdict is about that
    organization and nothing else, which is the whole reason the
    readings behind it are scoped commands (`tenant show shop`,
    `traffic show --org shop`) rather than the instance's documents
    filtered here. A screen that filtered would drop measurements, and
    dropping one is the one thing this console may not do."""
    bodies, _ = [], None
    for reading in readings:
        body, _ = _source(reading)
        bodies.append(body)
    v = verdict_of(readings)
    who = (f'<p class="subject"><a class="act act--quiet" href="/">all '
           f'organizations</a><b>{_e(subject)}</b></p>' if subject else "")
    head = (f'<header class="verdict" data-state="{v}">{who}'
            f'<p class="sentence">{_e(SENTENCE[v])}</p></header>')
    return (f'<main class="sereno" data-veredicto="{v}"'
            + (f' data-subject="{_e(subject)}"' if subject else "")
            + f'>{head}{"".join(bodies)}</main>')

# ── the whole page ───────────────────────────────────────────────────
# SKIN = share/console/sereno.css, and it is INLINED rather than linked.
# One document, one request, no static path to get wrong and nothing
# fetched from anywhere: the console is served on loopback and the file
# is 6 KB. Reading it is the only I/O this module does besides loading a
# case, and it is kept out of render() so that the pure function stays
# pure and check 122 can keep calling it with no filesystem at all.
SKIN = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "share", "console", "sereno.css")


FONTS = os.path.join(os.path.dirname(SKIN), "fonts")


def _inline_fonts(css):
    """Turn each `url("x.woff2")` into the bytes themselves.

    The faces are vendored in share/console/fonts/ and pinned by digest
    (see fonts.txt). Inlining them means the served page fetches
    NOTHING — not from a CDN, which this product never does, and not
    even from itself — so it renders identically over an SSH tunnel, on
    a laptop with no route out, and saved to a file.

    A face that cannot be read is left as it was: the stack in --ui
    falls back to the system's, and a console with the wrong typeface
    is still a console. Failing to draw over a font would be the page
    lying about something it can actually see.
    """
    import base64
    import re as _re

    def one(match):
        name = match.group(1)
        try:
            with open(os.path.join(FONTS, name), "rb") as fh:
                b64 = base64.b64encode(fh.read()).decode("ascii")
        except OSError:
            return match.group(0)
        return f'url(data:font/woff2;base64,{b64}) format("woff2")'

    return _re.sub(r'url\("([a-z0-9.-]+\.woff2)"\)\s*format\("woff2"\)', one, css)


def skin():
    try:
        with open(SKIN, encoding="utf-8") as fh:
            return _inline_fonts(fh.read())
    except OSError:
        # A console with no skin still has to draw: the states travel in
        # the attributes, and the text is readable unstyled. Saying so
        # is better than serving a blank page.
        return "/* the skin could not be read; the states are in the data-state attributes */"


def page(readings, title="aegis", subject=None):
    return ("<!doctype html>\n"
            '<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{_e(title)}</title><style>{skin()}</style></head>"
            f"<body>{render(readings, subject)}</body></html>\n")
