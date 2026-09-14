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


def _is_colour(value):
    """A colour this page will paint with, or nothing.

    IT GOES INTO A `style` ATTRIBUTE, and what arrives here came from
    somebody else's API. `#c0ffee` is a colour; `red; background:url(…)`
    is an injection, and the fact that GitHub is the one answering today
    is not a reason to hand its answer to a browser unread. Six or three
    hexadecimal digits after a hash, and nothing else gets drawn."""
    import re as _re
    return bool(value and _re.fullmatch(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})", str(value)))


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


# WHAT EACH SERVICE IS WRITTEN IN. It does not come from the contract —
# a contract says `http`, which is what a service is TO THE PLATFORM —
# and the console does not go and ask: `aegis repos` does, and this
# reads its document like any other. A language nobody could measure
# comes back as None and is drawn as nothing, never as a guess.
def languages_of(readings):
    by = {}
    for r in readings or []:
        if (r.get("comando") or "").startswith("repos list"):
            for step in (r.get("documento") or {}).get("steps") or []:
                name = step.get("step", "")
                if not name.startswith("repo:"):
                    continue
                for u in step.get("sirve") or []:
                    by[(u.get("organizacion"), u.get("servicio"))] = {
                        "lenguaje": step.get("lenguaje"),
                        "color": step.get("color"),
                        "repo": name.split(":", 1)[1]}
    return by


def _panel_organizations(doc, states, ctx=None):
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
        langs = (ctx or {}).get('langs') or {}
        # THE COLOUR IS GITHUB'S OWN, measured in the same answer as the
        # language's name. It is what this screen shows instead of a
        # logo: every one of those is a trademark with a usage policy,
        # and a platform whose argument is «measured, and it says where
        # it got it» does not redistribute somebody else's mark.
        #
        # A language nobody could measure gets NO dot, rather than a
        # grey one — an absent mark reads as «no language», and a grey
        # one reads as a language that happens to be grey.
        def _srv(sv):
            known = langs.get((name, sv.get("nombre"))) or {}
            colour = known.get("color")
            dot = (f'<i class="dot" style="background:{_e(colour)}"></i>'
                   if _is_colour(colour) else "")
            return (f'<span class="srv" data-kind="{_e(sv.get("tipo"))}">{dot}'
                    f'{_e(sv.get("nombre"))}'
                    f'<i>{_e(known.get("lenguaje") or sv.get("tipo"))}</i></span>')
        chips = "".join(_srv(sv) for sv in services)
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


def _panel_traffic(doc, states, ctx=None):
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


def _panel_round(doc, states, ctx=None):
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


def _panel_edge(doc, states, ctx=None):
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


def _panel_capacity(doc, states, ctx=None):
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


def _panel_builds(doc, states, ctx=None):
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
                # Drawn unmeasured, and NOT counted towards the
                # section's verdict for the same reason the links above
                # are not: these two are measured elsewhere ALWAYS, by
                # design, so letting them decide would make this panel
                # say «nobody looked» on every instance for ever. A
                # signal that never changes is a signal nobody reads,
                # which is this project's own line about `degraded`.
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
        # THE LINKS ARE DRAWN WITH THEIR OWN STATE AND DO NOT DECIDE THE
        # SECTION'S. A build the anti-loop skipped has four unmeasured
        # links because nothing ran, and letting those colour the whole
        # panel made a healthy instance's deployments read «nobody
        # looked» next to a page that said everything was in order. Two
        # verdicts about the same thing, and the louder one was wrong.
        #
        # Nothing is lost by it: each link carries its own `data-state`
        # in the HTML, which is where check 122 reads them, and the
        # step's own state is already in `states` above.
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


def _panel_tenant(doc, states, ctx=None):
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


def _panel_backup(doc, states, ctx=None):
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


def _panel_repos(doc, states, ctx=None):
    """The repositories, seen from the end that matters on this screen:
    the ones NOTHING is running. A list of what is already deployed is
    the panel above under another name; this is the only place that says
    what could be."""
    free, total, deployed = [], 0, 0
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "")
        if name == "repos":
            total, deployed = step.get("total", 0), step.get("deployed", 0)
            continue
        if not name.startswith("repo:") or step.get("sirve"):
            continue
        free.append((step.get("empujado") or "", name.split(":", 1)[1],
                     step.get("lenguaje"), step.get("color")))
    if not (doc.get("steps") or []):
        states.add(UNSEEN)
        return (f'<p class="empty" data-state="{UNSEEN}">GitHub could not be asked, '
                f'which is not the same as having no repositories</p>')
    free.sort(reverse=True)
    # THE MOST RECENTLY PUSHED FIRST and only a handful drawn, because
    # forty rows is a list nobody reads. The count is said out loud so
    # that what is collapsed is COUNTED and not hidden.
    shown = free[:8]
    rows = "".join(
        f'<li data-state="{FINE}">'
        f'<a class="mono" href="/new?repo={_e(name)}">{_e(name)}</a>'
        + (f'<span class="srv">'
           + (f'<i class="dot" style="background:{_e(colour)}"></i>'
              if _is_colour(colour) else "")
           + f'{_e(lang)}</span>' if lang else "")
        + '</li>' for _when, name, lang, colour in shown)
    rest = (f'<li class="rest" data-state="{FINE}">and {len(free) - len(shown)} more '
            f'that nothing is running</li>' if len(free) > len(shown) else "")
    return (f'<div class="facts-row">{_fact("repositories", _num(total))}'
            f'{_fact("deployed", _num(deployed))}'
            f'{_fact("could be", _num(len(free)))}</div>'
            f'<ul class="tail repos">{rows}{rest}</ul>')


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
    "repos list": _panel_repos,
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


def _source(reading, ctx=None):
    if reading.get("sin_documento") or reading.get("documento") is None:
        return _blind(reading), {UNSEEN}
    doc = reading["documento"]
    steps = doc.get("steps") or []
    states = set()
    panel = panel_for(reading.get("comando") or "")
    if panel and steps:
        body = [panel(doc, states, ctx)]
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


# ── the panel ────────────────────────────────────────────────────────
# WHAT THIS SCREEN WAS UNTIL 2026-09-14, and it took the operator saying
# it plainly: «estamos buscando un panel, no un scroll hacia abajo con
# info». It was one section per command, stacked, in the order the
# commands were written. That is the shape of the DOCUMENT. A panel has
# a shape of its own: what you came to see fills it, and everything else
# is an indicator you open when it asks you to.
#
# So the body is the PROJECTS, assembled across readings — the contract
# says which exist, the traffic says what reached them, the builds say
# what happened to their last push — and every source keeps its whole
# panel one click away inside a `<details>`. Nothing is lost by
# summarising, because the summary is not a replacement: the document is
# still there, underneath, and check 122 renders every case to make sure
# no state fell out on the way.
#
# `<details>` and not a script: this console has never served one, and a
# fold that works with JavaScript disabled is a fold that works.

# One short figure per source, for the line you read without opening it.
# A panel whose indicators all say the same word is a panel nobody reads
# twice, so each one says the number it is actually about.
def _headline(command, doc):
    steps = (doc or {}).get("steps") or []
    def count(pred):
        return sum(1 for st in steps if pred(st))
    if command == "check":
        bad = count(lambda st: SCREEN.get(st.get("state")) != FINE)
        return f"{len(steps)} sections" + (f" · {bad} asking" if bad else "")
    if command.startswith("edge"):
        bad = count(lambda st: SCREEN.get(st.get("state")) != FINE)
        return f"{len(steps)} hostnames" + (f" · {bad} asking" if bad else "")
    if command.startswith("capacity"):
        for st in steps:
            if st.get("step") == "capacity:memory" and st.get("free_human"):
                return f"{st['free_human']} free"
        return f"{len(steps)} readings"
    if command.startswith("traffic"):
        for st in steps:
            if st.get("step") == "traffic:total":
                return f"{_num(st.get('requests', 0))} req · {_window(st)}"
        got = sum(st.get("requests", 0) for st in steps if "requests" in st)
        return f"{_num(got)} req" if got else f"{len(steps)} readings"
    if command.startswith("builds"):
        return f"{count(lambda st: st.get('step','').startswith('build:'))} pushes"
    if command.startswith("repos"):
        for st in steps:
            if st.get("step") == "repos":
                return (f"{_num(st.get('total', 0))} repos · "
                        f"{_num(st.get('unclaimed', 0))} free")
        return f"{len(steps)} repos"
    if command.startswith("tenant"):
        return f"{count(lambda st: st.get('step','').startswith('service:'))} services"
    if command.startswith("data remote"):
        for st in steps:
            if st.get("age_hours") is not None:
                return f"{st['age_hours']:g} h old"
        return "off-site copy"
    if command.startswith("org"):
        return f"{len(steps)} contracts"
    return f"{len(steps)} readings"


def _vital(reading, ctx=None):
    """One source, folded. The line says what it is, how it is and one
    number; opening it gives the panel that was there before.

    IT OPENS BY ITSELF WHEN IT IS NOT FINE. That is «the order is the
    alarm» made structural: what needs somebody is already open when the
    page loads, and what does not is a line."""
    body, states = _source(reading, ctx)
    inner = body.split(">", 1)[1].rsplit("</section>", 1)[0]
    doc = reading.get("documento")
    state = worst(states) if states else UNSEEN
    command = reading.get("comando") or ""
    figure = (_headline(command, doc) if doc is not None
              else "could not be looked at")
    # THE AGE COMES OUT TO THE SUMMARY LINE. It was inside the fold, and
    # a measurement whose age you have to click to see is a measurement
    # read as if it were now — which is the oldest lie a dashboard
    # tells, and the one check 127 exists for.
    inner = inner.replace(_age(reading), "", 1)
    return (f'<section class="source vital" data-state="{state}" '
            f'data-command="{_e(command)}" data-rc="{_e(reading.get("rc"))}"'
            f'{_when(reading)}>'
            f'<details{" open" if state != FINE else ""}>'
            f'<summary><b>{_e(command)}</b>'
            f'<span class="fig">{_e(figure)}</span>'
            f'{_age(reading)}{_chip(state, state)}</summary>'
            f'<div class="vital-body">{inner}</div></details></section>')


def _per_org(readings, key):
    """What each organization's own step says, out of a source that
    reports per organization. Used to put the traffic on a project's
    card without the traffic panel losing it: the same measure drawn in
    two places loses nothing, and the card is where somebody looks."""
    out = {}
    for r in readings or []:
        for st in (r.get("documento") or {}).get("steps") or []:
            name = st.get("step", "")
            if name.startswith(key):
                out[name.split(":", 1)[1]] = st
    return out


def _window_read(readings):
    """How many builds the reading covers. A card that shows no push has
    to say «none among the last N»: «nothing» on a screen reads as «this
    never deployed», and those are different facts."""
    for r in readings or []:
        for st in (r.get("documento") or {}).get("steps") or []:
            if st.get("step") == "builds" and st.get("leidos"):
                return st["leidos"]
    return None


def _last_push(readings, org, services):
    """The most recent build of any image this organization is built
    from. It is the one fact a person looks for on a project card and it
    lived in a panel of its own until today."""
    mine = {sv.get("nombre") for sv in services or []}
    best = None
    for r in readings or []:
        if not (r.get("comando") or "").startswith("builds"):
            continue
        for st in (r.get("documento") or {}).get("steps") or []:
            if not st.get("step", "").startswith("build:"):
                continue
            image = st.get("image") or ""
            # `<org>-<service>` is how a tenant's image is named, and the
            # organization's own name is how a one-repo tenant's is.
            tail = image[len(org) + 1:] if image.startswith(org + "-") else None
            if image != org and (tail is None or tail not in mine):
                continue
            when = st.get("when") or ""
            if best is None or when > (best.get("when") or ""):
                best = st
    return best


def _project_card(step, readings, langs):
    org = step.get("step", "").split(":", 1)[-1]
    state = SCREEN.get(step.get("state"), UNSEEN)
    if not step.get("valid", True):
        return (f'<article class="proj" data-state="{state}">'
                f'<h3>{_e(org)}</h3>{_chip(state, "contract refused")}'
                f'<p class="why">{_e(step.get("error", ""))}</p></article>')
    services = step.get("servicios") or []
    dots = "".join(
        (lambda k: f'<i class="dot" title="{_e(k.get("lenguaje") or sv.get("tipo"))}"'
                   + (f' style="background:{_e(k.get("color"))}"'
                      if _is_colour(k.get("color")) else ' data-plain="1"')
                   + '></i>')(langs.get((org, sv.get("nombre"))) or {})
        for sv in services)
    figs = []
    t = _per_org(readings, "traffic:").get(org)
    if t and "requests" in t:
        figs.append(_fact("requests", _num(t.get("requests", 0))))
        figs.append(_fact("5xx", _num(t.get("errors", 0))))
    push = _last_push(readings, org, services)
    window = _window_read(readings)
    chain = ""
    if push:
        chain = ('<p class="push"><span class="mono">'
                 + _e(f'{push.get("image", "?")} #{push.get("build", "?")}')
                 + '</span>'
                 + "".join(f'<span class="link" data-state="{SCREEN.get(v, UNSEEN)}">'
                           f'{_e(k[0])}</span>'
                           for k, v in (push.get("links") or {}).items())
                 + '</p>')
    elif window:
        chain = (f'<p class="push none">no push among the last {_e(window)} read</p>')
    extras = []
    if step.get("bucket"):
        extras.append("bucket")
    if step.get("ai"):
        extras.append(f"ai {step['ai']}")
    return (f'<article class="proj" data-state="{state}">'
            f'<h3><a href="/org/{_e(org)}">{_e(org)}</a></h3>'
            f'<p class="host mono">{_e(step.get("dominio") or "no public domain")}</p>'
            f'<div class="dots">{dots}<span class="n">{len(services)}</span></div>'
            + (f'<div class="facts-row">{"".join(figs)}</div>' if figs else "")
            + chain
            + f'<p class="meta">quota <b>{_e(step.get("cuota"))}</b>'
            + (f' · {_e(" · ".join(extras))}' if extras else "") + '</p></article>')


def _projects(reading, readings, ctx):
    """The body of the panel: one card per organization, assembled
    ACROSS readings. The contract says which exist, the traffic says what
    reached them, the builds say what happened to their last push — and
    until today those were three sections a screen apart."""
    doc = reading.get("documento")
    if doc is None:
        body, _ = _source(reading, ctx)
        return body
    langs = (ctx or {}).get("langs") or {}
    cards, states = [], set()
    for step in doc.get("steps") or []:
        states.add(SCREEN.get(step.get("state"), UNSEEN))
        if not step.get("step", "").startswith("organization:"):
            continue
        cards.append(_project_card(step, readings, langs))
    if not cards:
        states.add(UNSEEN)
        cards.append(f'<p class="empty" data-state="{UNSEEN}">no contract was read</p>')
    state = worst(states) if states else UNSEEN
    return (f'<section class="source projects" data-state="{state}" '
            f'data-command="{_e(reading.get("comando"))}" '
            f'data-rc="{_e(reading.get("rc"))}"{_when(reading)}>'
            f'<h2>projects</h2>{_age(reading)}'
            f'<div class="grid">{"".join(cards)}</div></section>')


def _services_of(reading, ctx):
    """The body of ONE organization's panel: its services as cards."""
    doc = reading.get("documento")
    if doc is None:
        body, _ = _source(reading, ctx)
        return body
    states = set()
    cards, rest = [], []
    for step in doc.get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        kind, _, what = step.get("step", "").partition(":")
        if kind != "service":
            continue
        ready, desired = step.get("ready"), step.get("desired")
        count = f"{ready}/{desired}" if desired is not None else "none"
        bits = [f'<span class="srv">{_e(step.get("tipo", "?"))}</span>']
        if step.get("publico"):
            bits.append(f'<span class="srv mono">{_e(step["publico"])}</span>')
        if step.get("volume"):
            bits.append(f'<span class="srv">{_e(step.get("volume_size") or "disk")}</span>')
        cards.append(
            f'<article class="proj" data-state="{state}">'
            f'<h3>{_e(what)}</h3>{_chip(state, count)}'
            f'<div class="dots">{"".join(bits)}</div>'
            + (f'<p class="why">{_e(_WHY.get(step.get("why"), step.get("why")))}</p>'
               if step.get("why") else "")
            + '</article>')
    if not cards:
        states.add(UNSEEN)
        cards.append(f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>')
    state = worst(states) if states else UNSEEN
    # Everything the tenant document says that is NOT a service — the
    # namespace, the routing, the quota, what nothing claims — still has
    # to reach the screen, so the whole panel goes underneath.
    body, _ = _source(reading, ctx)
    inner = body.split(">", 1)[1].rsplit("</section>", 1)[0]
    # The whole panel goes underneath, MINUS its own age line: the age
    # belongs to the reading and the reading is drawn once. Two ages for
    # one measurement is two chances to read the wrong one.
    inner = inner.replace(_age(reading), "", 1)
    return (f'<section class="source projects" data-state="{state}" '
            f'data-command="{_e(reading.get("comando"))}" '
            f'data-rc="{_e(reading.get("rc"))}"{_when(reading)}>'
            f'<h2>services</h2>{_age(reading)}'
            f'<div class="grid">{"".join(cards)}</div>'
            f'<details class="fold"><summary><b>everything it measured</b>'
            f'</summary><div class="vital-body">{inner}</div></details></section>')


def render(readings, subject=None):
    """The panel. `subject` names WHO it is about — an organization — and
    when it is given the verdict is about that organization and nothing
    else, which is why the readings behind it are scoped commands rather
    than the instance's documents filtered here. A screen that filtered
    would drop measurements, and dropping one is the one thing this
    console may not do."""
    ctx = {"langs": languages_of(readings)}
    v = verdict_of(readings)

    body, vitals = [], []
    for reading in readings:
        command = reading.get("comando") or ""
        if not subject and command == "org list":
            body.append(_projects(reading, readings, ctx))
        elif subject and command.startswith("tenant show"):
            body.append(_services_of(reading, ctx))
        else:
            vitals.append(_vital(reading, ctx))

    where = (f'<a class="act act--quiet" href="/">all projects</a>' if subject
             else '<span class="mark">aegis</span>')
    action = (f'<a class="act" href="/org/{_e(subject)}/edit">edit the contract</a>'
              if subject else '<a class="act" href="/new">new project</a>')
    bar = (f'<header class="bar" data-state="{v}">{where}'
           + (f'<b class="who">{_e(subject)}</b>' if subject else "")
           + f'<p class="sentence">{_e(SENTENCE[v])}</p>{action}</header>')
    return (f'<main class="sereno panel" data-veredicto="{v}"'
            + (f' data-subject="{_e(subject)}"' if subject else "")
            + f'>{bar}'
            # THE PROJECTS BEFORE THE INDICATORS. The bar already said
            # how the whole thing is, in a sentence; what somebody opens
            # this for is underneath it, and the instance's vitals come
            # after because they support that rather than compete with
            # it.
            + "".join(body)
            + (f'<section class="vitals">{"".join(vitals)}</section>' if vitals else "")
            + '</main>')


# ── the one screen that writes ───────────────────────────────────────
# EVERY CHOICE ON IT COMES OUT OF `aegis org schema`. Nothing below
# writes down a type, a quota plan or a field: a list typed into a form
# is a list that stops being true the day somebody adds a type, and the
# failure is the quiet one — the console cannot create something the
# platform supports and nothing says so. Check 097 holds the schema and
# the validator to each other; this function only has to refuse to
# invent.
#
# AND NO SCRIPT. The console has never served one and this screen does
# not change that: `default-src 'none'` with no `script-src` is a
# promise the page cannot quietly stop keeping. What that costs is that
# a field cannot be greyed out as the type changes, so the rules travel
# as TEXT beside each type, and the validator —one validator, the same
# one `aegis org apply` runs— is what refuses.
SERVICE_ROWS = 3


def _field(name, label, value="", kind="text", hint="", **attrs):
    extra = "".join(f' {k}="{_e(v)}"' for k, v in attrs.items())
    return (f'<label class="field"><span class="label">{_e(label)}</span>'
            f'<input type="{kind}" name="{_e(name)}" id="{_e(name)}" '
            f'value="{_e(value)}"{extra}></label>'
            + (f'<p class="hint">{_e(hint)}</p>' if hint else ""))


def _choice(name, label, options, value="", hint=""):
    if not options:
        # An empty list is NOT «there are none». The schema says so with
        # a state; the form has to say it with words, or somebody
        # invents a plan because the console showed none.
        return (f'<div class="field" data-state="{UNSEEN}">'
                f'<span class="label">{_e(label)}</span>'
                f'<p class="hint">nobody could read the list of options, so none is '
                f'offered. This is not a platform without them.</p></div>')
    picks = "".join(
        f'<label class="pick"><input type="radio" name="{_e(name)}" '
        f'value="{_e(o)}"{" checked" if o == value or (not value and i == 0) else ""}>'
        f'<span>{_e(o)}</span></label>' for i, o in enumerate(options))
    return (f'<div class="field"><span class="label">{_e(label)}</span>'
            f'<div class="picks">{picks}</div>'
            + (f'<p class="hint">{_e(hint)}</p>' if hint else "") + "</div>")


def _schema_of(doc):
    return {s.get("step", ""): s for s in (doc or {}).get("steps") or []}


# WHAT A LANGUAGE SUGGESTS A SERVICE IS. A SUGGESTION AND NOTHING MORE:
# it is written on the form as a suggestion, the person changes it in one
# click, and nothing downstream reads it. The measured half is the repo
# and its language; this table is the courtesy of not making somebody
# pick from six words when five of them are obviously wrong.
#
# It errs towards `http`, which is the type that refuses least: a static
# front declared as http starts and serves, while an http service
# declared static has nowhere to run. Wrong in the direction that fails
# loudly is the only acceptable direction for a guess.
SUGGESTS = {
    "astro": "estatico", "html": "estatico", "css": "estatico",
    "svelte": "estatico", "vue": "estatico", "mdx": "estatico",
}


def suggestion_for(language):
    return SUGGESTS.get((language or "").lower(), "http")


def repo_in(readings, name):
    """One repository, out of `aegis repos list`'s document. Returns the
    step or None — and None is what a name that is not there gets, which
    is the only safe answer to a name that came off a URL."""
    for r in readings or []:
        if (r.get("comando") or "").startswith("repos list"):
            for step in (r.get("documento") or {}).get("steps") or []:
                if step.get("step") == f"repo:{name}":
                    return step
    return None


def import_fields(repo, language, url=None):
    """A repository, as the beginning of a contract.

    ONLY THE NAME AND THE REPOSITORY ARE MEASURED. The organization's
    name is the repository's, trimmed to what the validator accepts; the
    service's is the repository's too; the type is a SUGGESTION and the
    form says so. Everything else is left empty on purpose — a hostname
    invented from a repository name is a CNAME nobody later knows why is
    there, and this screen has been careful about that from the start.
    """
    import re as _re
    base = _re.sub(r"[^a-z0-9-]", "-", (repo or "").lower()).strip("-")
    base = _re.sub(r"-+", "-", base)[:30]
    if not _re.match(r"^[a-z][a-z0-9-]{2,29}$", base):
        base = ""
    # The contract names a repository the way git clones it over ssh, and
    # the owner is not this screen's to invent: it comes out of the URL
    # GitHub itself returned. With no URL the field is left EMPTY rather
    # than filled with a guessed owner — a form with a wrong value in it
    # is worse than a form with a blank, because a blank asks.
    ssh = ""
    if url:
        tail = url.split("github.com", 1)[-1].lstrip("/:").removesuffix(".git")
        if "/" in tail:
            ssh = f"git@github.com:{tail}.git"
    return {"organizacion": base, "dominio": "", "cuota": "",
            "servicio0.nombre": "web", "servicio0.tipo": suggestion_for(language),
            "servicio0.publico": "/", "servicio0.repo": ssh}


def render_form(schema, token, filled=None, problem=None, action="/new",
                existing=0, subject=None):
    """The screen where an organization is described by somebody who
    does not write YAML. It writes NOTHING: what it submits is a
    proposal, and the next screen is the plan.

    `existing` is how many of the service rows are already in the
    contract. They are drawn first and marked, because on an edit the
    rows that are on the screen are the ones that survive — see
    `contract_from_edit`."""
    by = _schema_of(schema)
    filled = filled or {}
    types = {k.split(":", 1)[1]: v for k, v in by.items() if k.startswith("tipo:")}
    offerable = sorted(k for k, v in types.items() if v.get("disponible", True))
    quotas = (by.get("cuota") or {}).get("opciones") or []
    sizes = (by.get("tamano") or {}).get("opciones") or []

    back = f'/org/{_e(subject)}' if subject else '/'
    where = f'back to {_e(subject)}' if subject else 'all organizations'
    head = (f'<header class="verdict" data-state="{FINE}">'
            f'<p class="subject"><a class="act act--quiet" href="{back}">{where}'
            f'</a><b>{_e(subject) if subject else "a new organization"}</b></p>'
            f'<p class="sentence">'
            + ('Nothing is changed yet. The next screen is the plan, and even that '
               'writes nothing.' if subject else
               'Nothing here is created yet. The next screen is the plan, and even '
               'that writes nothing.')
            + '</p></header>')
    trouble = ""
    if problem:
        # THE VALIDATOR'S OWN WORDS, not a paraphrase. It explains which
        # field and why, at length and on purpose, and shortening that
        # here would be this console deciding it knows better than the
        # one program that actually refused.
        trouble = (f'<section class="source" data-state="{WRONG}">'
                   f'<h2>this is not a contract yet</h2>{_chip(WRONG, "refused")}'
                   f'<pre class="why">{_e(problem)}</pre></section>')

    # A form filled from a repository carries ONE guess —the type— and
    # it has to be legible as a guess. Everything else on the screen was
    # measured or typed by a person.
    suggested = bool((filled or {}).get("servicio0.repo")) and not existing
    rows = []
    for i in range(max(SERVICE_ROWS, existing + 1)):
        n = f"servicio{i}"
        picked = filled.get(f"{n}.tipo", "")
        options = "".join(
            f'<option value="{_e(t)}"{" selected" if t == picked else ""}>{_e(t)}</option>'
            for t in offerable)
        rows.append(
            f'<fieldset class="row"{" data-existing=\"1\"" if i < existing else ""}>'
            f'<legend>service {i + 1}'
            + (" <i>already in the contract</i>" if i < existing else
               (" <i>at least one</i>" if not i and not existing else ""))
            + '</legend>'
            f'{_field(n + ".nombre", "name", filled.get(n + ".nombre", ""))}'
            f'<label class="field"><span class="label">type</span>'
            f'<select name="{n}.tipo" id="{n}.tipo"><option value=""></option>'
            f'{options}</select></label>'
            + ('<p class="hint">suggested from the language: change it if it is '
               'wrong</p>' if suggested and not i else "")
            + f'{_field(n + ".puerto", "port", filled.get(n + ".puerto", ""))}'
            f'{_field(n + ".publico", "public path", filled.get(n + ".publico", ""))}'
            f'{_field(n + ".repo", "repository", filled.get(n + ".repo", ""))}'
            + (f'{_field(n + ".tamano", "size", filled.get(n + ".tamano", ""))}'
               if sizes else "")
            + '</fieldset>')

    # What each type is and what it refuses, as words, because there is
    # no script to grey a field out with. Every line of it is the
    # schema's, which is the validator's.
    legend = []
    for kind in sorted(types):
        spec = types[kind]
        if not spec.get("disponible", True):
            legend.append(f'<li data-state="{UNSEEN}">{_chip(UNSEEN, kind)}'
                          f'<span class="note">{_e(spec.get("porque_no", "not offerable here"))}'
                          f'</span></li>')
            continue
        needs = ", ".join(spec.get("requiere") or []) or "nothing else"
        refuses = ", ".join(spec.get("prohibe") or [])
        note = f"needs {needs}" + (f" · refuses {refuses}" if refuses else "")
        if spec.get("porque"):
            note += f" — {spec['porque']}"
        legend.append(f'<li data-state="{FINE}">{_chip(FINE, kind)}'
                      f'<span class="note">{_e(note)}</span></li>')

    keep = ('<p class="hint">The services already in the contract stay: this screen '
            'adds and changes, it does not remove. Removing one is `aegis org` by '
            'hand, which says what it is about to do.</p>' if existing else "")
    body = (f'<section class="source" data-state="{FINE}">'
            f'<h2>{"the organization" if not subject else "what it is"}</h2>{keep}'
            f'<form method="post" action="{_e(action)}">'
            f'<input type="hidden" name="token" value="{_e(token)}">'
            f'{_field("organizacion", "name", filled.get("organizacion", ""), hint=(by.get("contract") or {}).get("nombre_patron", ""))}'
            f'{_field("dominio", "public hostname", filled.get("dominio", ""), hint=(by.get("contract") or {}).get("dominio_si", ""))}'
            f'{_choice("cuota", "ceiling", quotas, filled.get("cuota", ""), "the contract names a plan and never a number")}'
            f'<div class="rows">{"".join(rows)}</div>'
            f'<ul class="tail legend">{"".join(legend)}</ul>'
            f'<button class="act" type="submit">see the plan</button>'
            f'</form></section>')
    return f'<main class="sereno" data-veredicto="{FINE}">{head}{trouble}{body}</main>'


def contract_from_form(fields, schema):
    """The form's fields, as a contract. Pure, and deliberately dumb.

    IT DROPS NOTHING THE PERSON FILLED IN. A `puerto` typed on a worker
    travels into the contract and the validator refuses it, by name,
    with its own paragraph. The alternative —quietly discarding a field
    the type does not allow— would have the console silently disagree
    with what somebody wrote, and they would go looking for a port they
    are sure they set.

    An empty field is not a value: it is absent. That is the difference
    between «no public hostname» and «a hostname that is the empty
    string», and only one of the two is a thing somebody meant.
    """
    import yaml

    def value(name):
        v = (fields.get(name) or "").strip()
        return v or None

    by = _schema_of(schema)
    contract = {"version": (by.get("contract") or {}).get("version", 1)}
    for key in ("organizacion", "dominio", "cuota"):
        if value(key):
            contract[key] = value(key)
    services = []
    for i in range(SERVICE_ROWS):
        n = f"servicio{i}"
        row = {k: value(f"{n}.{k}") for k in
               ("nombre", "tipo", "puerto", "publico", "repo", "tamano")}
        if not any(row.values()):
            continue
        service = {}
        for key in ("nombre", "tipo"):
            if row[key]:
                service[key] = row[key]
        if row["puerto"]:
            # A port that is not a number stays a STRING and reaches the
            # validator as one. Coercing it here would turn a typo into
            # a different typo.
            service["puerto"] = int(row["puerto"]) if row["puerto"].isdigit() else row["puerto"]
        for key in ("publico", "repo", "tamano"):
            if row[key]:
                service[key] = row[key]
        services.append(service)
    if services:
        contract["servicios"] = services
    text = yaml.safe_dump(contract, allow_unicode=True, sort_keys=False, width=88)
    return contract, text


# The fields the form actually shows. Everything else a contract can
# carry — `usa`, `almacenamiento`, `ai` and its whole list of tasks —
# is NOT on this screen, and that is exactly why the edit is built by
# CHANGING the contract rather than by rebuilding it from the form.
SHOWN = ("nombre", "tipo", "puerto", "publico", "repo", "tamano")


def fields_of_contract(contract):
    """A contract, as the form's fields. It exists so that the edit
    screen opens showing what is actually there rather than an empty
    form somebody has to retype."""
    contract = contract or {}
    filled = {"organizacion": contract.get("organizacion") or "",
              "dominio": contract.get("dominio") or "",
              "cuota": contract.get("cuota") or ""}
    for i, sv in enumerate(contract.get("servicios") or []):
        n = f"servicio{i}"
        for key in SHOWN:
            v = sv.get(key)
            filled[f"{n}.{key}"] = "" if v is None else str(v)
    return filled


def refuse_edit(contract, current):
    """Why this edit may not be saved over that organization, or None.

    THE ONE THING AN EDIT WILL NOT DO IS DROP A SERVICE. A form that
    renders three rows over an organization with five services deletes
    two of them, silently, at the moment somebody pressed a button that
    said «save». That is not an edit anybody asked for. So the services
    that exist are the floor: every one of them comes out the other
    side, and a name field somebody cleared is a REFUSAL rather than a
    removal.

    Removing a service is `aegis org` by hand, reading what it says. It
    is a different decision — a database being removed takes its volume
    with it — and this screen does not offer it at all.

    It is a function of the CONTRACT and not of the form, so that the
    same rule can be applied twice: once to what the form built, and
    again to whatever body comes back on the way in. The second time is
    not paranoia — a body can be replayed, edited by hand, or posted
    from a page drawn ten minutes ago over an organization that has
    changed since.
    """
    contract = contract or {}
    current = current or {}
    have = [sv.get("nombre") for sv in current.get("servicios") or []]
    kept = [sv.get("nombre") for sv in contract.get("servicios") or []]
    lost = [n for n in have if n and n not in kept]
    if lost:
        return (f"this would remove {', '.join(lost)} from the contract, and removing "
                f"a service is not an edit: a database takes its volume with it. Every "
                f"service that is already there has to still be there when you save. "
                f"To remove one, `aegis org` does it by hand and says what it is about "
                f"to do first.")
    was = current.get("organizacion")
    if was and contract.get("organizacion") != was:
        # Renaming would write a DIFFERENT file and leave the old one
        # in place: two contracts, one namespace, and a screen that
        # says it saved.
        return ("an organization cannot be renamed from here: this would write a "
                "second contract and leave the first one where it is. The name is the "
                "identity.")
    return None


def contract_from_edit(fields, schema, current):
    """The edited contract: THE CURRENT ONE, CHANGED. Never rebuilt.

    THE BUG THIS SHAPE EXISTS TO PREVENT, and it was measured on
    2026-09-13 by opening this screen over a real contract. The form
    shows six fields per service. A contract carries more: `usa`, the
    `almacenamiento` block, the whole `ai` section with its list of
    tasks. Rebuilding the contract from the form dropped every one of
    them — and `usa` is OPTIONAL, so the validator had nothing to say.
    Somebody adding a database to their shop would have silently deleted
    the four capabilities its API declares, and found out when the
    NetworkPolicies stopped letting it reach any of them.

    So the current contract is the floor. The form's fields are applied
    ON TOP of it, service by service and only for what it shows; new
    rows are appended; and anything this screen does not display comes
    out the other side exactly as it went in.
    """
    import copy
    import yaml

    current = current or {}
    contract = copy.deepcopy(current)
    for key in ("organizacion", "dominio", "cuota"):
        v = (fields.get(key) or "").strip()
        if v:
            contract[key] = v
        elif key in contract and key != "organizacion":
            # A hostname somebody cleared is a hostname removed, and
            # that is a legitimate edit: an organization with nothing
            # public has nobody to expose.
            del contract[key]

    services = list(contract.get("servicios") or [])
    out, i = [], 0
    while True:
        n = f"servicio{i}"
        if not any(f"{n}.{k}" in fields for k in SHOWN):
            break
        row = {k: (fields.get(f"{n}.{k}") or "").strip() for k in SHOWN}
        base = copy.deepcopy(services[i]) if i < len(services) else {}
        if not any(row.values()) and not base:
            i += 1
            continue
        for key in SHOWN:
            if row[key]:
                base[key] = (int(row[key]) if key == "puerto" and row[key].isdigit()
                             else row[key])
            elif key in base and i >= len(services):
                del base[key]
            elif key in base and not row[key]:
                # A field cleared on a service that EXISTS removes it.
                # That is a change to a service, not a removal of one,
                # and `refuse_edit` is what guards the removal.
                del base[key]
        if base:
            out.append(base)
        i += 1
    # Any service the form did not reach at all stays. The rows are
    # grown to fit in `render_form`, so this is the belt to that brace.
    for j in range(i, len(services)):
        out.append(copy.deepcopy(services[j]))
    if out:
        contract["servicios"] = out

    refused = refuse_edit(contract, current)
    if refused:
        return None, None, refused
    text = yaml.safe_dump(contract, allow_unicode=True, sort_keys=False, width=88)
    return contract, text, None


def render_edit(schema, current, token, filled=None, problem=None):
    """The same form, opened over an organization that exists.

    It shows every service it has, because the ones on the screen are
    the ones that survive: this screen adds and changes, and it does
    not remove.
    """
    org = (current or {}).get("organizacion") or ""
    filled = filled or fields_of_contract(current or {})
    body = render_form(schema, token, filled, problem,
                       action=f"/org/{org}/edit", existing=len(
                           (current or {}).get("servicios") or []),
                       subject=org)
    return body


def _diff(before, after):
    """What changes in the contract itself, line by line.

    THE MOST USEFUL THING ON AN EDIT'S SCREEN. The plan below says which
    generated files would change, and that is a fact about the
    machinery. This says what the person actually did — two lines added,
    a word replaced — and it is the thing they can check against what
    they meant.
    """
    import difflib
    rows = []
    for line in difflib.unified_diff(before.splitlines(), after.splitlines(),
                                     lineterm="", n=2):
        if line.startswith("---") or line.startswith("+++"):
            continue
        mark = ("add" if line.startswith("+") else
                "del" if line.startswith("-") else
                "at" if line.startswith("@@") else "same")
        rows.append(f'<div class="dl" data-d="{mark}">{_e(line)}</div>')
    if not rows:
        return ('<p class="empty" data-state="fine">the contract is exactly as it '
                'was: nothing to change</p>')
    return f'<div class="diff mono">{"".join(rows)}</div>'


def _errand(after, org, platform):
    """What the console did after writing, and what is left for a
    person. THE THREE THAT ARE LEFT ARE SHOWN AS COMMANDS, literally and
    ready to paste, because each one is left for a reason somebody
    should be able to read: the commit is what makes a file in a working
    tree harmless, `sync` speaks to the cluster, and `app apply` creates
    things on GitHub, which is somebody else's machine."""
    rows = []
    for step in after or []:
        if step.get("sin_documento"):
            state, said = UNSEEN, step["sin_documento"]
        elif step.get("rc") == 0:
            doc = step.get("documento") or {}
            n = len(doc.get("steps") or [])
            state, said = FINE, f"{n} file(s) written"
        else:
            state = WRONG
            doc = step.get("documento") or {}
            bad = [x.get("step") for x in doc.get("steps") or []
                   if x.get("state") in ("wrong", "not-evaluable")]
            said = ", ".join(bad[:3]) or f"rc {step.get('rc')}"
        rows.append(f'<li data-state="{state}">{_chip(state, step.get("que", "?"))}'
                    f'<span class="mono">{_e(step.get("paso"))}</span>'
                    f'<span class="note">{_e(said)}</span></li>')
    left = [
        (f"cd {platform} && git add -A && git commit -m 'org: {org}' && git push",
         "the commit is yours: it is what makes a file in a working tree harmless, "
         "because ArgoCD reads the remote"),
        ("aegis sync root", "this one speaks to the cluster"),
        (f"aegis app apply {org}",
         "this one creates the repository, the deploy key and the webhook ON GITHUB"),
    ]
    steps_left = "".join(
        f'<li><code class="cmd mono">{_e(c)}</code>'
        f'<span class="note">{_e(why)}</span></li>' for c, why in left)
    return (f'<section class="source" data-state="{FINE}">'
            f'<h2>what the console did</h2>'
            f'<ul class="tail">{"".join(rows)}</ul></section>'
            f'<section class="source" data-state="{ATTENTION}">'
            f'<h2>what is left for you, and why</h2>'
            f'<ol class="left">{steps_left}</ol></section>')


def render_plan(doc, contract_text, token, written=None, before=None, org=None,
                after=None, platform=None):
    """What would change, and the one button that writes.

    THE SENTENCE MATTERS MORE THAN THE LIST. Writing the contract
    changes nothing that is running: ArgoCD reads the remote, and a file
    in a working tree is a file in a working tree. What makes an
    organization exist is a commit, and that is the operator's to make.
    """
    states = set()
    files, stages = [], []
    for step in (doc or {}).get("steps") or []:
        state = SCREEN.get(step.get("state"), UNSEEN)
        states.add(state)
        name = step.get("step", "")
        if name.startswith("stage:") or name.startswith("contract:"):
            stages.append(f'<li data-state="{state}">{_chip(state, name.split(":", 1)[0])}'
                          f'<span class="mono">{_e(name.split(":", 1)[1])}</span></li>')
            continue
        files.append(f'<li data-state="{state}">{_chip(state, step.get("change", "?"))}'
                     f'<span class="mono">{_e(name)}</span></li>')
    v = worst(states) if states else UNSEEN
    editing = before is not None
    if written:
        sentence = ("The contract and everything derived from it are in your "
                    "repository, and nothing is running yet. Three things are left "
                    "and each one is left for a reason.")
        action = (f'<p class="host mono">{_e(written)}</p>'
                  f'<a class="act act--quiet" href="/">all organizations</a>')
    else:
        sentence = "Nothing has been written. This is what would change."
        back = f"/org/{_e(org)}/edit" if editing and org else "/new"
        where = f"/org/{_e(org)}/write" if editing and org else "/new/write"
        action = (f'<form method="post" action="{where}">'
                  f'<input type="hidden" name="token" value="{_e(token)}">'
                  f'<input type="hidden" name="contrato" value="{_e(contract_text)}">'
                  f'<button class="act" type="submit">'
                  + ("write it over the contract" if editing else "write the contract")
                  + f'</button>'
                  f'<a class="act act--quiet" href="{back}">change something</a></form>')
    head = (f'<header class="verdict" data-state="{v}">'
            f'<p class="subject"><a class="act act--quiet" href="/">all organizations</a>'
            f'<b>the plan</b></p><p class="sentence">{_e(sentence)}</p></header>')
    # THE DIFF FIRST, and the generated files after. What the person did
    # is two lines of YAML; which of the six derived manifests that
    # touches is a fact about the machinery, true and second.
    change = (f'<section class="source" data-state="{FINE}">'
              f'<h2>what you changed</h2>{_diff(before, contract_text)}</section>'
              if editing else "")
    errand = (_errand(after, org, platform) if written and after else "")
    return (f'<main class="sereno" data-veredicto="{v}">{head}{change}{errand}'
            f'<section class="source" data-state="{v}"><h2>what would change</h2>'
            + (f'<ul class="tail">{"".join(files)}</ul>' if files else
               f'<p class="empty" data-state="{UNSEEN}">nothing was planned</p>')
            + (f'<ul class="tail">{"".join(stages)}</ul>' if stages else "")
            + f'</section>'
            f'<section class="source" data-state="{FINE}">'
            f'<h2>the contract{" as it would be" if editing else ""}</h2>'
            f'<pre class="contract mono">{_e(contract_text)}</pre>{action}</section>'
            f'</main>')


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


def wrap(body, title="aegis"):
    """A whole document around a body that is already drawn. `page`
    renders readings; the screens that are not readings —the form, the
    plan— come through here so that the skin is inlined in exactly one
    place."""
    return ("<!doctype html>\n"
            '<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{_e(title)}</title><style>{skin()}</style></head>"
            f"<body>{body}</body></html>\n")


def page(readings, title="aegis", subject=None):
    return ("<!doctype html>\n"
            '<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{_e(title)}</title><style>{skin()}</style></head>"
            f"<body>{render(readings, subject)}</body></html>\n")
