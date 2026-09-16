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


def _plan_choice(by, value, back):
    """The plan, picked by what it is for. Each option carries the
    sentence its plan declares and its numbers in words, out of the
    schema — never typed here — and the way to a plan of your own sits
    beside them, because «none of these fits» is a real answer."""
    from .screens import _plan_words
    cuota = by.get("cuota") or {}
    options = cuota.get("opciones") or []
    if not options:
        return (f'<div class="field" data-state="{UNSEEN}"><span class="label">plan</span>'
                f'<p class="hint">nobody could read the list of plans, so none is offered. '
                f'This is not a platform without them.</p></div>')
    words = cuota.get("descripciones") or {}
    numbers = cuota.get("numeros") or {}
    picks = "".join(
        f'<label class="plan-pick"><input type="radio" name="cuota" value="{_e(o)}"'
        f'{" checked" if o == value or (not value and i == 0) else ""}>'
        f'<span class="plan-body"><b class="mono">{_e(o)}</b>'
        + (f'<span class="desc">{_e(words.get(o))}</span>' if words.get(o) else "")
        + f'<span class="nums">{_e(_plan_words(numbers.get(o)))}</span></span></label>'
        for i, o in enumerate(options))
    return (f'<div class="field"><span class="label">plan</span>'
            f'<div class="plan-picks">{picks}</div>'
            f'<p class="hint plain">How much of the machine the whole project may take. '
            f'{_e(cuota.get("nota") or "")} None of these fits? '
            f'<a href="/plans/new?back={_e(back)}">Create a plan of your own</a>.</p></div>')


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


def rows_in(fields):
    """How many service rows a form carries: the count it declares, or
    the rows actually present, whichever is larger. There is no fixed
    number — a project has as many services as its plan holds, and the
    plan preview is what says whether they fit."""
    fields = fields or {}
    declared = 0
    try:
        declared = int(fields.get("rows") or 0)
    except (TypeError, ValueError):
        declared = 0
    present = 0
    for k in fields:
        if k.startswith("servicio") and "." in k:
            try:
                present = max(present, int(k[len("servicio"):k.index(".")]) + 1)
            except ValueError:
                pass
    return max(declared, present)


def import_box_for(readings):
    """The repositories nothing runs yet, for the top of the new-project
    screen. Empty when the instance's readings are not to hand."""
    from .screens import import_box, reading_for
    r = reading_for(readings, "repos list")
    return import_box(r) if r is not None else ""


# What a project may NEED, ticked rather than declared: a database is a
# service the platform provides, and a person should not have to know
# that a PostgreSQL is «a service of type postgres named datos» to get
# one. Each need is (the contract's word, the label, the name the
# provided service gets, the sentence). Whether a need is OFFERED comes
# from the schema — `usa.opciones` says which exist, `tipo:<x>.disponible`
# whether the platform can deliver it here — never from this table.
NEEDS = (
    ("postgres", "a PostgreSQL database", "datos",
     "tables: users, orders, anything relational. Bundled and copied off-site."),
    ("redis", "a Redis cache", "cola",
     "a cache or a queue in memory. What it holds is a copy and may be evicted."),
    ("mongodb", "a MongoDB database", "mongo", "documents instead of tables."),
    ("bucket", "a bucket for files", None,
     "uploads and files, S3-style, in this instance's own object store."),
    ("internet", "reach the internet", None,
     "by default a service reaches nothing outside. Tick this if it calls an API, "
     "sends mail or fetches anything."),
)
PROVIDED_NAME = {k: name for k, _l, name, _d in NEEDS if name}
DEFAULT_PORT = "8080"
DEFAULT_PATH = "/"
DEFAULT_SERVICE = "web"


def render_form(schema, token, filled=None, problem=None, action="/new",
                existing=0, subject=None, before=""):
    """The screen where a project is described by somebody who does not
    write YAML. It writes NOTHING: what it submits is a proposal, and
    the next screen is the plan.

    THE SHORT PATH IS THE DEFAULT. Most projects are one repository
    that is a static site or a web service, maybe with a database. So
    the screen asks for that and nothing more: what it is (three cards),
    where it comes from, what it needs (ticked), which plan. The
    contract's own words travel underneath every card. More services
    are one click away, as many as the plan holds, and each one is a
    plain row.

    `existing` is how many of the service rows are already in the
    contract. They are drawn first and marked, because on an edit the
    rows that are on the screen are the ones that survive — see
    `contract_from_edit`."""
    by = _schema_of(schema)
    filled = filled or {}
    types = {k.split(":", 1)[1]: v for k, v in by.items() if k.startswith("tipo:")}
    offerable = sorted(k for k, v in types.items() if v.get("disponible", True))
    # The words a person reads beside the contract's own. The VALUE the
    # form submits is the contract's word, always: the label is for the
    # person, and the validator never sees it.
    from .screens import KIND, KIND_ABOUT, KIND_ICON, _icon
    sizes = (by.get("tamano") or {}).get("opciones") or []
    # Small to large, which is how a person reads a ladder; the schema
    # lists them alphabetically. A size the ladder does not know goes
    # after the ones it does.
    ladder = ("chico", "mediano", "grande")
    sizes = [z for z in ladder if z in sizes] + [z for z in sizes if z not in ladder]
    size_words = (by.get("tamano") or {}).get("descripciones") or {}
    default_size = (by.get("tamano") or {}).get("por_omision") or (sizes[0] if sizes else "")
    usa_options = set((by.get("usa") or {}).get("opciones") or [])

    back = f'/projects/{_e(subject)}' if subject else '/'
    where = f'back to {_e(subject)}' if subject else 'all projects'
    head = (f'<header class="verdict" data-state="{FINE}">'
            f'<p class="subject"><a class="act act--quiet" href="{back}">{where}'
            f'</a><b>{_e(subject) if subject else "a new project"}</b></p>'
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

    def val(key, default=""):
        # A default only where the person has said nothing at all: a
        # field they emptied stays empty, and on an edit every field is
        # already there.
        return filled[key] if key in filled else default

    # ── the main service, guided ─────────────────────────────────────
    n = "servicio0"
    kind0 = val(f"{n}.tipo")
    cards = []
    for k in [x for x in ("estatico", "http", "worker") if x in offerable]:
        cards.append(
            f'<label class="kind-pick"><input type="radio" name="{n}.tipo" value="{_e(k)}"'
            f'{" checked" if k == kind0 else ""}><span class="plan-body">'
            f'<b>{_icon(KIND_ICON.get(k, "web"))}{_e(KIND.get(k, k))} '
            f'<span class="mono">{_e(k)}</span></b>'
            f'<span class="desc">{_e(KIND_ABOUT.get(k, ""))}</span></span></label>')
    kind_hint = ('suggested from what the repository is written in: change it if it is '
                 'wrong' if suggested else "what runs, out of what the platform can build")
    size_cards = "".join(
        f'<label class="kind-pick"><input type="radio" name="{n}.tamano" value="{_e(z)}"'
        f'{" checked" if z == val(n + ".tamano", default_size) else ""}>'
        f'<span class="plan-body"><b>{_e(z)}</b>'
        f'<span class="desc">{_e(size_words.get(z) or "")}</span></span></label>'
        for z in sizes)
    main = (f'<div class="main-svc">'
            f'<div class="field wide"><span class="label">what it is</span>'
            f'<div class="kind-picks">{"".join(cards)}</div><p class="hint">{kind_hint}</p></div>'
            f'<div class="wide">{_field(n + ".repo", "repository", val(n + ".repo"), hint="the git URL it is built from, as you would clone it: git@github.com:you/your-app.git")}</div>'
            f'<div class="cell">{_field(n + ".nombre", "service name", val(n + ".nombre", DEFAULT_SERVICE), hint="how it is called inside the project; `web` is fine for the first one")}</div>'
            f'<div class="cell">{_field(n + ".publico", "public path", val(n + ".publico", DEFAULT_PATH), hint="where it answers on the hostname: `/` for the site, `/api` for an API; not for a worker")}</div>'
            f'<div class="cell">{_field(n + ".puerto", "port", val(n + ".puerto", DEFAULT_PORT), hint="what a web service listens on; leave it as is unless you know otherwise. Not used by a static site or a worker")}</div>'
            + (f'<div class="field wide"><span class="label">size</span>'
               f'<div class="size-picks">{size_cards}</div>'
               f'<p class="hint">what one copy of it may reserve and burst to, inside the plan</p></div>'
               if sizes else "")
            + '</div>')

    # ── what it needs, ticked ────────────────────────────────────────
    needs = []
    for key, label, _name, desc in NEEDS:
        if key not in usa_options:
            continue
        spec = types.get(key) or {}
        available = spec.get("disponible", True) if key in types else True
        checked = " checked" if filled.get(f"needs.{key}") else ""
        if available:
            needs.append(f'<label class="need"><input type="checkbox" name="needs.{_e(key)}" '
                         f'value="on"{checked}><span><b>{_e(label)}</b>'
                         f'<span class="desc">{_e(desc)}</span></span></label>')
        else:
            needs.append(f'<label class="need off"><input type="checkbox" disabled><span>'
                         f'<b>{_e(label)}</b><span class="desc">not offerable here: '
                         f'{_e(spec.get("porque_no") or "")}</span></span></label>')
    needs_hint = ('Ticking a database adds it to the project as a service the platform '
                  'provides, and lets the web services and workers reach it. On an edit, '
                  'ticking adds; unticking removes nothing.' if existing else
                  'Ticking a database adds it to the project as a service the platform '
                  'provides, and lets the web services and workers reach it.')

    # ── more services, plain rows ────────────────────────────────────
    total = max(rows_in(filled), existing, 1)
    rows = []
    for i in range(1, total):
        n = f"servicio{i}"
        picked = val(f"{n}.tipo")
        options = "".join(
            f'<option value="{_e(t)}"{" selected" if t == picked else ""}>{_e(t)}'
            f'{" · " + _e(KIND[t]) if t in KIND else ""}</option>'
            for t in offerable)
        size_opts = "".join(
            f'<option value="{_e(z)}"{" selected" if z == val(n + ".tamano") else ""}>{_e(z)}</option>'
            for z in sizes)
        rows.append(
            f'<fieldset class="row"{" data-existing=\"1\"" if i < existing else ""}>'
            f'<legend>service {i + 1}'
            + (" <i>already in the contract</i>" if i < existing else "")
            + '</legend>'
            f'{_field(n + ".nombre", "name", val(n + ".nombre"))}'
            f'<label class="field"><span class="label">kind</span>'
            f'<select name="{n}.tipo" id="{n}.tipo"><option value=""></option>'
            f'{options}</select></label>'
            f'{_field(n + ".repo", "repository", val(n + ".repo"))}'
            f'{_field(n + ".publico", "public path", val(n + ".publico"))}'
            f'{_field(n + ".puerto", "port", val(n + ".puerto"))}'
            + (f'<label class="field"><span class="label">size</span>'
               f'<select name="{n}.tamano" id="{n}.tamano"><option value=""></option>'
               f'{size_opts}</select></label>' if sizes else "")
            + '</fieldset>')
    more = (f'<details class="more-svc"{" open" if total > 1 else ""}>'
            f'<summary>More services'
            + (f' · {total - 1}' if total > 1 else "")
            + '<span class="note">an API beside the site, a worker, a second database. '
            'As many as the plan holds: the plan preview says whether they fit.</span>'
            '</summary>'
            + (f'<div class="rows">{"".join(rows)}</div>' if rows else "")
            + f'<div class="rows-actions"><button class="act act--quiet" type="submit" '
            f'name="do" value="add">add another service</button>'
            + ('<span class="note">a row left empty is not a service</span>' if rows else "")
            + '</div></details>')

    keep = ('<p class="hint plain">The services already in the contract stay: this screen '
            'adds and changes, it does not remove. Removing one is `aegis org` by hand, '
            'which says what it is about to do.</p>' if existing else "")
    contract = by.get("contract") or {}
    name_hint = ("a short lowercase name; it becomes the namespace and the prefix of "
                 "every image"
                 + (f' · pattern {contract["nombre_patron"]}' if contract.get("nombre_patron")
                    else ""))
    host_hint = ("the hostname people will type, like shop.example.test"
                 + (f' · needed when {contract["dominio_si"]}' if contract.get("dominio_si")
                    else ""))
    body = (f'<section class="source" data-state="{FINE}">'
            f'<h2>{"the project" if not subject else "what it is"}</h2>{keep}'
            f'<form method="post" action="{_e(action)}">'
            f'<input type="hidden" name="token" value="{_e(token)}">'
            f'<input type="hidden" name="rows" value="{total}">'
            f'{_field("organizacion", "name", val("organizacion"), hint=name_hint)}'
            f'{_field("dominio", "public hostname", val("dominio"), hint=host_hint)}'
            f'<h3 class="sub">what runs</h3>{main}'
            f'<h3 class="sub">what it needs</h3><div class="needs">{"".join(needs)}</div>'
            f'<p class="hint plain">{needs_hint}</p>'
            f'{_plan_choice(by, val("cuota"), action)}'
            f'{more}'
            f'<button class="act" type="submit">see the plan</button>'
            f'</form></section>')
    return f'<main class="sereno" data-veredicto="{FINE}">{head}{trouble}{before}{body}</main>'


def _apply_needs(contract, services, needs, current=None, new_from=0):
    """The needs, as contract. A database ticked is a service the
    platform provides, appended once; a bucket is `almacenamiento`;
    every need lets the web services and workers reach it (`usa`).

    ADD-ONLY, and careful on an edit: a need the contract already has
    changes nothing on the services that were there — otherwise opening
    the edit screen and pressing save would rewrite every `usa` — and
    reaches only the services this edit ADDS (`new_from` and after). A
    need ticked for the first time reaches them all.
    """
    current = current or {}
    had = set()
    for sv in current.get("servicios") or []:
        if sv.get("tipo") in PROVIDED_NAME:
            had.add(sv["tipo"])
        for u in sv.get("usa") or []:
            had.add(u)
    if (current.get("almacenamiento") or {}).get("bucket"):
        had.add("bucket")
    taken = {sv.get("nombre") for sv in services}
    for need in needs:
        if need in PROVIDED_NAME and not any(sv.get("tipo") == need for sv in services):
            name = PROVIDED_NAME[need]
            while name in taken:
                name += "-2"
            services.append({"nombre": name, "tipo": need})
            taken.add(name)
        if need == "bucket":
            contract.setdefault("almacenamiento", {})["bucket"] = True
        for i, sv in enumerate(services):
            if sv.get("tipo") not in ("http", "worker"):
                continue
            if need in had and i < new_from:
                continue
            usa = list(sv.get("usa") or [])
            if need not in usa:
                usa.append(need)
                sv["usa"] = usa


def contract_from_form(fields, schema):
    """The form's fields, as a contract. Pure, and deliberately dumb.

    IT DROPS NOTHING THE PERSON FILLED IN. A `puerto` typed on a worker
    travels into the contract and the validator refuses it, by name,
    with its own paragraph. The alternative —quietly discarding a field
    the type does not allow— would have the console silently disagree
    with what somebody wrote, and they would go looking for a port they
    are sure they set.

    THE FORM'S OWN DEFAULTS ARE NOT SOMETHING THE PERSON FILLED IN. The
    screen puts `8080` in the port and `/` in the public path before
    anybody types, so that the short path needs no typing; a static
    site refuses a port and a worker refuses a public path, and a
    person who picked «static site» did not ask for 8080. Exactly those
    two defaults, on exactly the kinds that refuse them, are left out.
    Anything typed over them travels.

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
    for i in range(rows_in(fields)):
        n = f"servicio{i}"
        row = {k: value(f"{n}.{k}") for k in
               ("nombre", "tipo", "puerto", "publico", "repo", "tamano")}
        if not any(row.values()):
            continue
        if row["tipo"] and row["tipo"] != "http" and row["puerto"] == DEFAULT_PORT:
            row["puerto"] = None
        if row["tipo"] == "worker" and row["publico"] == DEFAULT_PATH:
            row["publico"] = None
        if row["tipo"] in PROVIDED_NAME and row["tamano"]:
            # A provided service has no size of its own (the platform's
            # catalogue decides), and the form's default size was never
            # meant for it.
            row["tamano"] = None
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
    needs = [k for k, _l, _n, _d in NEEDS if fields.get(f"needs.{k}")]
    if needs:
        _apply_needs(contract, services, needs)
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
    form somebody has to retype. The needs it already has come ticked,
    and `rows` says how many services it carries."""
    contract = contract or {}
    filled = {"organizacion": contract.get("organizacion") or "",
              "dominio": contract.get("dominio") or "",
              "cuota": contract.get("cuota") or ""}
    services = contract.get("servicios") or []
    for i, sv in enumerate(services):
        n = f"servicio{i}"
        for key in SHOWN:
            v = sv.get(key)
            filled[f"{n}.{key}"] = "" if v is None else str(v)
    filled["rows"] = str(len(services))
    for sv in services:
        if sv.get("tipo") in PROVIDED_NAME:
            filled[f"needs.{sv['tipo']}"] = "on"
        for u in sv.get("usa") or []:
            filled[f"needs.{u}"] = "on"
    if (contract.get("almacenamiento") or {}).get("bucket"):
        filled["needs.bucket"] = "on"
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

    # What it needs, ticked: ADD-ONLY, and only where the contract does
    # not already have it — see `_apply_needs`. Unticking removes
    # nothing, like everything else on this screen.
    needs = [k for k, _l, _n, _d in NEEDS if fields.get(f"needs.{k}")]
    if needs:
        now = list(contract.get("servicios") or [])
        _apply_needs(contract, now, needs, current=current, new_from=len(services))
        contract["servicios"] = now

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
                       action=f"/projects/{org}/edit", existing=len(
                           (current or {}).get("servicios") or []),
                       subject=org)
    return body


def _in_words(contract_text):
    """The contract, as sentences. THE FIRST THING ON THE PLAN SCREEN,
    because a person checks what they meant against words, not against
    a list of generated files."""
    import yaml
    from .screens import KIND, USES
    try:
        c = yaml.safe_load(contract_text) or {}
    except yaml.YAMLError:
        return ""
    if not isinstance(c, dict):
        return ""
    rows = [f'<li><b class="mono">{_e(c.get("organizacion") or "?")}</b>'
            + (f', at <span class="mono">{_e(c["dominio"])}</span>' if c.get("dominio") else
               ", with no public hostname")
            + f', plan <b class="mono">{_e(c.get("cuota") or "?")}</b>.</li>']
    for sv in c.get("servicios") or []:
        kind = sv.get("tipo")
        if kind in PROVIDED_NAME:
            rows.append(f'<li><b class="mono">{_e(sv.get("nombre"))}</b>: '
                        f'{_e(KIND.get(kind, kind))}, provided by the platform.</li>')
            continue
        bits = [KIND.get(kind, kind or "?")]
        if sv.get("publico"):
            bits.append(f'answering at <span class="mono">{_e(sv["publico"])}</span>')
        if sv.get("puerto"):
            bits.append(f'on port {_e(sv["puerto"])}')
        if sv.get("repo"):
            bits.append(f'built from <span class="mono">{_e(sv["repo"])}</span>')
        if sv.get("tamano"):
            bits.append(f'size {_e(sv["tamano"])}')
        line = f'<li><b class="mono">{_e(sv.get("nombre"))}</b>: {", ".join(bits)}'
        if sv.get("usa"):
            line += f'; may reach {_e(", ".join(USES.get(u, u) for u in sv["usa"]))}'
        rows.append(line + '.</li>')
    if (c.get("almacenamiento") or {}).get("bucket"):
        rows.append('<li>A bucket for files.</li>')
    if c.get("ai"):
        tasks = (c["ai"] or {}).get("tareas") or []
        rows.append(f'<li>AI plan <b class="mono">{_e((c["ai"] or {}).get("plan", "?"))}</b>, '
                    f'{len(tasks)} task{"s" if len(tasks) != 1 else ""}.</li>')
    return (f'<section class="source" data-state="{FINE}"><h2>in plain words</h2>'
            f'<ul class="words">{"".join(rows)}</ul></section>')


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
                  f'<a class="act act--quiet" href="/">all projects</a>')
    else:
        sentence = "Nothing has been written. This is what would change."
        back = f"/projects/{_e(org)}/edit" if editing and org else "/new"
        where = f"/projects/{_e(org)}/write" if editing and org else "/new/write"
        action = (f'<form method="post" action="{where}">'
                  f'<input type="hidden" name="token" value="{_e(token)}">'
                  f'<input type="hidden" name="contrato" value="{_e(contract_text)}">'
                  f'<button class="act" type="submit">'
                  + ("write it over the contract" if editing else "write the contract")
                  + f'</button>'
                  f'<a class="act act--quiet" href="{back}">change something</a></form>')
    head = (f'<header class="verdict" data-state="{v}">'
            f'<p class="subject"><a class="act act--quiet" href="/">all projects</a>'
            f'<b>the plan</b></p><p class="sentence">{_e(sentence)}</p></header>')
    # THE DIFF FIRST, and the generated files after. What the person did
    # is two lines of YAML; which of the six derived manifests that
    # touches is a fact about the machinery, true and second.
    change = (f'<section class="source" data-state="{FINE}">'
              f'<h2>what you changed</h2>{_diff(before, contract_text)}</section>'
              if editing else "")
    errand = (_errand(after, org, platform) if written and after else "")
    words = _in_words(contract_text)
    return (f'<main class="sereno" data-veredicto="{v}">{head}{words}{change}{errand}'
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


def wrap(body, title="aegis", instance=None, active="projects", subject=None):
    """A whole document around a body that is already drawn. The
    screens that are not readings —the form, the plan— come through
    here, and when the instance's readings are given they get the same
    frame as every other screen: the menu, its dots, when the instance
    was read. Without them the body is served bare, which is what the
    checks that render a form on its own get."""
    if instance is not None:
        from . import screens
        body = screens.frame(body, instance, active, subject)
    return ("<!doctype html>\n"
            '<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{_e(title)}</title><style>{skin()}</style></head>"
            f"<body>{body}</body></html>\n")


# ── the screens ──────────────────────────────────────────────────────
# They live in lib/aegis/screens.py, organized the way people think —
# projects, deployments, domains, storage, security, the machine, the
# round — and this module keeps the vocabulary they translate from, the
# atoms they draw with, and the forms. `render` is the door the checks
# knock on: check 122 renders every case through it and reads the
# states back, check 127 counts the sources and their ages.
def render(readings, subject=None, view=None, instance=None):
    """A whole screen, as HTML: the overview by default, one project
    when `subject` names it, one concept page when `view` names it.
    `instance` is the instance's readings, used as context around a
    project's own (the contract, the languages, the menu's dots)."""
    from . import screens
    return screens.render(readings, subject=subject, view=view, instance=instance)


def page(readings, title="aegis", subject=None, view=None, instance=None):
    return ("<!doctype html>\n"
            '<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{_e(title)}</title><style>{skin()}</style></head>"
            f"<body>{render(readings, subject, view, instance)}</body></html>\n")


# ── a plan of your own ───────────────────────────────────────────────
# The same shape as the contract's screens: a form that writes nothing,
# a preview that writes nothing, and one button. What it writes is one
# named step in plans.yaml, through `aegis quota`, with the validation
# the shipped plans get. The seven numbers are asked for in a person's
# words, with the Kubernetes spelling beside each so that what is typed
# is what the file will say.
QUOTA_FIELDS = (
    ("requests.cpu", "CPU reserved",
     "what the scheduler sets aside for the whole project; the sizes of its services add up "
     "inside this. `2` is two cores, `500m` half a core"),
    ("requests.memory", "memory reserved", "`2Gi`, `512Mi`; the same rule as the CPU"),
    ("limits.cpu", "CPU ceiling", "what it may burst to; CPU over the ceiling is throttled"),
    ("limits.memory", "memory ceiling",
     "memory over the ceiling is killed, so this is a number somebody measured"),
    ("pods", "pods", "how many containers may run at once, replicas included"),
    ("persistentvolumeclaims", "disks", "how many volumes it may claim"),
    ("requests.storage", "disk",
     "the declared size of all its volumes together (`10Gi`); the provisioner does not "
     "enforce it on the disk itself"),
)


def _plans_in(listing):
    return {st["step"].split(":", 1)[1]: st for st in (listing or {}).get("steps") or []
            if st.get("step", "").startswith("plan:")}


def quota_from_form(fields):
    """The form's fields, as a plan. Pure and deliberately dumb: what is
    typed travels to `aegis quota`, which refuses in its own words."""
    v = lambda k: (fields.get(k) or "").strip()      # noqa: E731
    numbers = {k: v(k) for k, _l, _h in QUOTA_FIELDS}
    return {"nombre": v("nombre"), "desde": v("desde"), "descripcion": v("descripcion"),
            "numeros": numbers}


def render_quota_start(listing, token, back="/plans"):
    """Where a new plan starts: from one that exists. Chosen first and
    on its own screen because there is no script to copy the numbers
    across when a radio changes."""
    plans = _plans_in(listing)
    from .screens import _plan_words
    if not plans:
        body = (f'<section class="source" data-state="{UNSEEN}"><h2>start from a plan</h2>'
                f'<p class="empty">nobody could read the plans, so there is nothing to start '
                f'from. This is not a platform without them.</p></section>')
    else:
        rows = "".join(
            f'<a class="plan-start" href="/plans/new?from={_e(n)}&amp;back={_e(back)}">'
            f'<span class="plan-body"><b class="mono">{_e(n)}</b>'
            + (f'<span class="desc">{_e(st.get("descripcion"))}</span>' if st.get("descripcion") else "")
            + f'<span class="nums">{_e(_plan_words(st.get("numeros")))}</span></span>'
            f'<span class="act act--quiet small">Start from it</span></a>'
            for n, st in sorted(plans.items()))
        body = (f'<section class="source" data-state="{FINE}"><h2>start from a plan</h2>'
                f'<p class="lead">A new plan is a copy of one that exists, changed where you '
                f'say. Pick the closest.</p><div class="plan-starts">{rows}</div></section>')
    head = (f'<header class="verdict" data-state="{FINE}">'
            f'<p class="subject"><a class="act act--quiet" href="{_e(back)}">back</a>'
            f'<b>a new plan</b></p><p class="sentence">Nothing is written yet. A plan is a '
            f'named step in the catalogue; a contract names it and never a number.</p></header>')
    return f'<main class="sereno" data-veredicto="{FINE}">{head}{body}</main>'


def render_quota_form(listing, token, base=None, editing=None, filled=None, problem=None,
                      back="/plans"):
    """The seven numbers, in words, with the base's values already in
    the boxes. `editing` names a plan of your own being changed; then
    the name is fixed and there is no base."""
    plans = _plans_in(listing)
    source = plans.get(editing or base) or {}
    filled = dict(filled or {})
    if not filled:
        for k, _l, _h in QUOTA_FIELDS:
            filled[k] = (source.get("numeros") or {}).get(k, "")
        filled["descripcion"] = source.get("descripcion") or "" if editing else ""
        filled["nombre"] = editing or ""
        filled["desde"] = base or ""
    what = f'change {editing}' if editing else 'a new plan'
    head = (f'<header class="verdict" data-state="{FINE}">'
            f'<p class="subject"><a class="act act--quiet" href="{_e(back)}">back</a>'
            f'<b>{_e(what)}</b></p><p class="sentence">'
            + ("Nothing is changed yet. The next screen shows the plan as it would be, and "
               "even that writes nothing." if editing else
               f"Nothing is written yet. This starts from `{_e(base)}`; the next screen "
               f"shows the plan as it would be, and even that writes nothing.")
            + '</p></header>')
    trouble = ""
    if problem:
        trouble = (f'<section class="source" data-state="{WRONG}">'
                   f'<h2>this is not a plan yet</h2>{_chip(WRONG, "refused")}'
                   f'<pre class="why">{_e(problem)}</pre></section>')
    action = f'/plans/{_e(editing)}/edit' if editing else '/plans/new'
    numbers = "".join(
        f'{_field(k, f"{label}  ·  {k}", filled.get(k, ""), hint=hint)}'
        for k, label, hint in QUOTA_FIELDS)
    who = source.get("proyectos") or []
    warn = (f'<p class="hint plain" data-state="{ATTENTION}">'
            f'<b>{_e(", ".join(who))}</b> name{"s" if len(who) == 1 else ""} this plan. '
            f'Changing its numbers changes what {"it" if len(who) == 1 else "they"} may take, '
            f'once `aegis org apply` and a commit carry it to {"its" if len(who) == 1 else "their"} '
            f'namespace{"" if len(who) == 1 else "s"}.</p>' if editing and who else "")
    name_field = (f'<p class="field"><span class="label">name</span>'
                  f'<b class="mono">{_e(editing)}</b>'
                  f'<input type="hidden" name="nombre" value="{_e(editing)}"></p>'
                  if editing else
                  _field("nombre", "name", filled.get("nombre", ""),
                         hint="lowercase, digits and dashes, 3 to 30 characters; it is the word "
                              "a contract will name"))
    body = (f'<section class="source" data-state="{FINE}"><h2>the plan</h2>{warn}'
            f'<form method="post" action="{action}">'
            f'<input type="hidden" name="token" value="{_e(token)}">'
            f'<input type="hidden" name="desde" value="{_e(filled.get("desde", ""))}">'
            f'<input type="hidden" name="back" value="{_e(back)}">'
            f'{name_field}'
            f'{_field("descripcion", "what it is for", filled.get("descripcion", ""), hint="one sentence; it is what a person picks the plan by")}'
            f'<h3 class="sub">the seven numbers</h3><div class="numbers">{numbers}</div>'
            f'<button class="act" type="submit">see it</button></form></section>')
    return f'<main class="sereno" data-veredicto="{FINE}">{head}{trouble}{body}</main>'


def render_quota_preview(plan, token, capacity=None, editing=None, before=None, back="/plans"):
    """The plan as it would be written, and the one button.

    `capacity` is the instance's `capacity show` document, if it was
    read: with it the screen says how many projects of this plan the
    machine would still fit, which is the one question the numbers
    are chosen against."""
    from . import quantity
    from .screens import QUOTA_LABEL, _quantity_words
    numbers = plan.get("numeros") or {}
    rows = []
    for k, label, _h in QUOTA_FIELDS:
        was = (before or {}).get(k)
        changed = editing and was is not None and str(was) != str(numbers.get(k))
        rows.append(f'<tr{" class=changed" if changed else ""}><td>{_e(label)}</td>'
                    f'<td class="mono">{_e(numbers.get(k, ""))}</td>'
                    f'<td>{_e(_quantity_words(k, numbers.get(k)))}</td>'
                    + (f'<td class="note">was {_e(was)}</td>' if changed else "<td></td>")
                    + '</tr>')
    room = ""
    if capacity:
        free = {st.get("step"): st for st in capacity.get("steps") or []}
        mem, cpu = free.get("capacity:memory"), free.get("capacity:cpu")
        try:
            want_cpu = quantity.cpu(numbers.get("requests.cpu"))
            want_mem = quantity.mem(numbers.get("requests.memory"))
            n_cpu = (cpu or {}).get("free", 0) // want_cpu if want_cpu else None
            n_mem = (mem or {}).get("free", 0) // want_mem if want_mem else None
            fits = min(x for x in (n_cpu, n_mem) if x is not None)
            binding = "memory" if n_mem is not None and (n_cpu is None or n_mem <= n_cpu) else "CPU"
            room = (f'<p class="note">On this machine as it was last read, '
                    f'<b>{int(fits)}</b> more project{"s" if fits != 1 else ""} of this plan '
                    f'would fit; {binding} runs out first.</p>')
        except (TypeError, ValueError, KeyError):
            room = ""
    yaml_block = (f'cuota:\n  {plan.get("nombre")}:\n'
                  + (f'    descripcion: "{plan.get("descripcion")}"\n' if plan.get("descripcion") else "")
                  + "".join(f'    {k}: {numbers.get(k, "")}\n' for k, _l, _h in QUOTA_FIELDS))
    hidden = "".join(f'<input type="hidden" name="{_e(k)}" value="{_e(v)}">'
                     for k, v in (("nombre", plan.get("nombre")), ("desde", plan.get("desde")),
                                  ("descripcion", plan.get("descripcion")), ("back", back))
                     ) + "".join(f'<input type="hidden" name="{_e(k)}" value="{_e(numbers.get(k, ""))}">'
                                 for k, _l, _h in QUOTA_FIELDS)
    where = f'/plans/{_e(editing)}/write' if editing else '/plans/write'
    again = f'/plans/{_e(editing)}/edit' if editing else f'/plans/new?from={_e(plan.get("desde"))}'
    head = (f'<header class="verdict" data-state="{FINE}">'
            f'<p class="subject"><a class="act act--quiet" href="{_e(back)}">back</a>'
            f'<b>{_e(plan.get("nombre"))}</b></p><p class="sentence">Nothing has been written. '
            f'This is the plan as it would be in the catalogue.</p></header>')
    body = (f'<section class="source" data-state="{FINE}"><h2>the plan</h2>'
            + (f'<p class="lead">{_e(plan.get("descripcion"))}</p>' if plan.get("descripcion") else "")
            + f'<table class="rows"><thead><tr><th>number</th><th>as the file says it</th>'
            f'<th>in words</th><th></th></tr></thead><tbody>{"".join(rows)}</tbody></table>{room}'
            f'<pre class="contract mono">{_e(yaml_block)}</pre>'
            f'<form method="post" action="{where}">'
            f'<input type="hidden" name="token" value="{_e(token)}">{hidden}'
            f'<button class="act" type="submit">'
            + ("write it over the plan" if editing else "write it into the catalogue")
            + f'</button><a class="act act--quiet" href="{again}">change something</a></form>'
            f'</section>')
    return f'<main class="sereno" data-veredicto="{FINE}">{head}{body}</main>'


def render_quota_written(doc, name, back="/plans", editing=False):
    """What `aegis quota` said, and where to go next."""
    steps = (doc or {}).get("steps") or []
    st = next((x for x in steps if x.get("step") == f"plan:{name}"), steps[0] if steps else {})
    state = SCREEN.get(st.get("state"), UNSEEN)
    if state == FINE:
        sentence = (f"The plan is in the catalogue. A contract may name it now; nothing runs "
                    f"differently until one does, and `aegis org apply` and a commit carry it.")
        if editing and st.get("proyectos"):
            sentence = (f"The plan is changed in the catalogue. {', '.join(st['proyectos'])} "
                        f"name{'s' if len(st['proyectos']) == 1 else ''} it: `aegis org apply` "
                        f"and a commit are what carry the change to the cluster.")
    else:
        sentence = "The catalogue was not changed."
    head = (f'<header class="verdict" data-state="{state}">'
            f'<p class="subject"><a class="act act--quiet" href="/plans">every plan</a>'
            f'<b>{_e(name)}</b></p><p class="sentence">{_e(sentence)}</p></header>')
    body = (f'<section class="source" data-state="{state}"><h2>what aegis quota said</h2>'
            f'{_chip(state, STATE_WORD_FOR[state])}'
            + (f'<pre class="why">{_e(st.get("error"))}</pre>' if st.get("error") else "")
            + (f'<p class="host mono">{_e(st.get("fichero"))}</p>' if st.get("fichero") else "")
            + f'<p><a class="act" href="{_e(back)}">'
            + ("back to the form" if back not in ("/plans", "/") else "every plan")
            + '</a></p></section>')
    return f'<main class="sereno" data-veredicto="{state}">{head}{body}</main>'


STATE_WORD_FOR = {FINE: "written", WRONG: "refused", UNSEEN: "could not look",
                  ATTENTION: "attention", BUSY: "working"}
