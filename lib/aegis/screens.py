"""The console's screens, organized the way people already think.

WHY THIS MODULE EXISTS. Until 2026-09-16 the console drew the CLI: one
section per command, in the order the commands were written. That is
the shape of aegis, and it is not the shape of anybody's head. Somebody
who arrives from Vercel, from the AWS console or from GCP thinks in
projects, deployments, domains, storage, security — and the operator
said it plainly: «hay que ir por lo que la gente conoce». So this
module is a TRANSLATION LAYER: readings come in as the commands emit
them, and screens go out organized by concept, with a plain sentence
beside every word the platform uses.

WHAT IT DOES NOT DO. It measures nothing, guesses nothing and talks to
nothing: it is a pure function of the readings it is handed, like the
renderer it replaces, so that every screen can be drawn from a stored
case with no cluster and no browser (check 122 renders every case).

THE ONE RULE THAT SURVIVES THE REDESIGN. A reading is drawn ONCE as a
`<section class="source">` that names its command, carries when it was
taken and shows its age on the page. A screen may summarise, fold and
translate; it may not lose a state, invent one, or say «fine» when the
CLI said «I could not look». The state travels in `data-state`, never
in a word, so the words below may be rewritten freely.
"""
import datetime

from .console import (ATTENTION, BUSY, FINE, IS_FINE, LOOKED_AT, SCREEN, SENTENCE,
                      UNSEEN, WRONG, _bytes, _chip, _e, _is_colour, _num, _when,
                      languages_of, verdict_of, worst)

# ── the words a person reads ─────────────────────────────────────────
# The platform's vocabulary is the contract's, and the contract is in
# Spanish because the operator writes it. A person who does not write
# the contract should never have to learn it to read the screen, so
# every machine word gets its sentence here — and ONLY here, so that the
# translation is one table and not fifty scattered strings.
KIND = {
    "estatico": "static site", "http": "web service", "worker": "background worker",
    "postgres": "PostgreSQL database", "redis": "Redis cache", "mongodb": "MongoDB database",
}
KIND_ICON = {
    "estatico": "static", "http": "web", "worker": "worker",
    "postgres": "database", "mongodb": "database", "redis": "cache",
}
# What each kind IS, for the card a person picks it from. The schema
# still decides which kinds are offerable and what each needs and
# refuses; these are the words beside them.
KIND_ABOUT = {
    "estatico": "HTML, CSS and JS served as files: Astro, Vue, a built React app. "
                "Nothing of yours runs on the server.",
    "http": "A server that listens on a port: Node, PHP, Go, Java, Python. It can reach "
            "what you tick under «what it needs».",
    "worker": "Runs without listening: queues, scheduled jobs, processing. No public "
              "path and no port.",
}
USES = {
    "internet": "the internet", "postgres": "its PostgreSQL", "redis": "its Redis",
    "mongodb": "its MongoDB", "bucket": "its bucket", "ai": "the AI gateway",
}
QUOTA_WORD = {
    "limits.cpu": "CPU ceiling", "limits.memory": "memory ceiling",
    "requests.cpu": "CPU reserved", "requests.memory": "memory reserved",
    "requests.storage": "disk", "persistentvolumeclaims": "disks", "pods": "pods",
}
STATE_WORD = {FINE: "fine", WRONG: "wrong", ATTENTION: "attention",
              UNSEEN: "could not look", BUSY: "working"}
LINK_WORD = {"build": "built", "scan": "scanned", "sign": "signed", "digest": "pinned"}

# The round's sections, by the page they belong to. A section named
# here is drawn on that page AND on Health; one not named here is drawn
# on Health only, which is where every section is always drawn in full.
# Matching is on the step's name, which is data — the round emits it as
# the `step` field of its document, never as prose.
ROUND_PAGES = {
    "deployments": ("argocd", "stuck syncs", "CI quota", "CI webhooks", "every push built"),
    "domains": ("edge", "certificates", "whose the routing is"),
    "storage": ("backups",),
    "security": ("supply chain", "certificates", "CI webhooks", "whose the routing is",
                 "argocd"),
    "machine": ("node", "pods", "observability", "ai"),
}

# The sentences beside a machine word, for the tenant's document.
WHY = {
    "no-workload": "declared in the contract, and nothing in the cluster answers to it",
    "no-namespace": "the namespace does not exist",
    "unclaimed": "running here, and no service of the contract claims it",
    "unclaimed-volume": "a disk that is here and that no service of the contract "
                        "declares, so nothing copies it",
}
WHY_BACKUP = {
    "no-copy-at-the-destination": "this project holds data and there is no copy of "
                                  "it anywhere else",
    "destination-unreachable": "the destination did not answer, which is not the "
                               "same as having no copy",
    "no-readable-date": "there are copies and none has a readable date: their age "
                        "cannot be stated",
}

# Every page of the console, in the order of the menu. `feeds` names the
# commands whose readings give the page its dot in the menu and its
# peek on the overview: the menu can say «something is wrong on
# Storage» before anybody opens Storage.
PAGES = (
    ("projects", "Projects", "/", ("org list",)),
    ("deployments", "Deployments", "/deployments", ("builds show",)),
    ("domains", "Domains", "/domains", ("edge check",)),
    ("traffic", "Traffic", "/traffic", ("traffic show",)),
    ("storage", "Storage", "/storage", ("data remote status",)),
    ("plans", "Plans", "/plans", ("quota list",)),
    ("security", "Security", "/security", ()),
    ("machine", "Machine", "/machine", ("capacity show",)),
    ("health", "Health", "/health", ("check",)),
)

# The menu in three groups, the way the consoles people know are laid
# out: what you build and ship, what it does while it runs, and the
# platform under it. A flat list of nine is a list somebody scans twice.
MENU = (("Build & ship", ("projects", "deployments", "domains")),
        ("Run", ("traffic", "storage", "plans")),
        ("Platform", ("security", "machine", "health")))

LEAD = {
    "projects": "Each project is one of your applications: its services, its domain, "
                "its data. The contract in git says what it is; everything else on this "
                "screen was measured.",
    "deployments": "Every push to a project's repository becomes a build. Before it "
                   "runs it is scanned, signed and pinned by digest, and each of those "
                   "four links is measured on its own. A link nobody measured is "
                   "hatched, never a tick.",
    "domains": "The hostnames your contracts declare, whether each one exists at the "
               "edge, which service answers on each path, and the certificates behind "
               "them.",
    "traffic": "What actually reached each project, as the edge counted it. Requests, "
               "errors the server produced, and how slow the slowest tenth was.",
    "storage": "Disks live on this machine. Every project that holds data gets a copy "
               "sent off-site on a clock, and this screen says how old each copy is "
               "against that clock.",
    "security": "What runs is what was built here, scanned, signed and pinned. Each "
                "service reaches only what its contract names. This console listens on "
                "this machine and nowhere else.",
    "machine": "The one machine everything runs on: what is free, what is spoken for, "
               "and how many more projects of each plan would still fit.",
    "health": "The round: the whole platform measured against what the contracts "
              "declare, section by section. This is where every finding lives, "
              "including the ones the other screens summarise.",
    "plans": "A plan is the ceiling a project may take: what it reserves, what it may "
             "burst to, how many pods and disks. A contract names a plan and never a "
             "number, so changing the machine is one file and not thirty contracts. "
             "The plans aegis ships keep their numbers; the ones you add are yours.",
}
QUOTA_LABEL = {
    "requests.cpu": "CPU reserved", "requests.memory": "memory reserved",
    "limits.cpu": "CPU ceiling", "limits.memory": "memory ceiling",
    "pods": "pods", "persistentvolumeclaims": "disks", "requests.storage": "disk",
}


# ── atoms ────────────────────────────────────────────────────────────
def _time(iso):
    """An ISO timestamp as a person reads it. Nothing is computed from
    a clock: this module has none, so an age is shown as a date and not
    as «3 minutes ago», which would be a lie ten minutes later."""
    if not iso:
        return ""
    try:
        t = datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
    except ValueError:
        return str(iso)
    return t.strftime("%Y-%m-%d %H:%M")


def _age(reading):
    """When this reading was taken, ON THE PAGE. Check 127 counts one of
    these per reading: a measurement whose age is only in an attribute
    is read as if it were now."""
    w = reading.get("medido_en")
    return (f'<p class="age">read {_e(_time(w))}</p>' if w
            else '<p class="age">nobody recorded when this was read</p>')


def _icon(name):
    """A small line drawing for a kind of thing. Drawn here, by hand,
    and generic on purpose: the elephant and the gopher are somebody's
    trademark, and this product does not redistribute a mark. An inline
    SVG is part of the document, so the console's policy of fetching
    nothing holds."""
    paths = {
        "static": '<rect x="1.5" y="2.5" width="13" height="11" rx="1.5"/>'
                  '<path d="M1.5 6h13"/>',
        "web": '<circle cx="8" cy="8" r="6.5"/><path d="M1.5 8h13M8 1.5c2.5 2 2.5 11 0 13'
               'M8 1.5c-2.5 2-2.5 11 0 13"/>',
        "worker": '<path d="M9 1.5 3 9.5h4l-1 5 6-8H8z" stroke-linejoin="round"/>',
        "database": '<ellipse cx="8" cy="3.5" rx="6" ry="2"/>'
                    '<path d="M2 3.5v9c0 1.1 2.7 2 6 2s6-.9 6-2v-9M2 8c0 1.1 2.7 2 6 2s6-.9 6-2"/>',
        "cache": '<path d="M8 1.5 14.5 5 8 8.5 1.5 5z" stroke-linejoin="round"/>'
                 '<path d="M1.5 8 8 11.5 14.5 8M1.5 11 8 14.5 14.5 11"/>',
        "bucket": '<path d="M2 4h12l-1.2 9.5H3.2z" stroke-linejoin="round"/><path d="M5.5 4V2.5h5V4"/>',
        "ai": '<path d="M8 1.5 9.6 6.4 14.5 8 9.6 9.6 8 14.5 6.4 9.6 1.5 8l4.9-1.6z" '
              'stroke-linejoin="round"/>',
        "globe": '<circle cx="8" cy="8" r="6.5"/><path d="M1.5 8h13"/>',
        "shield": '<path d="M8 1.5 13.5 3.5v4.5c0 3-2.5 5.3-5.5 6.5C5 13.3 2.5 11 2.5 8V3.5z" '
                  'stroke-linejoin="round"/><path d="M5.5 8l2 2 3.5-3.5"/>',
        "chip": '<rect x="3.5" y="3.5" width="9" height="9" rx="1.5"/>'
                '<path d="M6 1.5v2M10 1.5v2M6 12.5v2M10 12.5v2M1.5 6h2M1.5 10h2M12.5 6h2M12.5 10h2"/>',
        "pulse": '<path d="M1.5 8h3l2-4.5 3 9 2-4.5h3"/>',
        "rocket": '<path d="M8 1.5c3 2 4 6 3 9H5c-1-3 0-7 3-9z" stroke-linejoin="round"/>'
                  '<path d="M5 10.5 3 13l2.2-.5M11 10.5 13 13l-2.2-.5M8 10.5v3"/>',
        "traffic": '<path d="M2 13V9M6 13V5M10 13V7M14 13V3"/>',
        "steps": '<path d="M1.5 14h4v-4h4V6h4V2" stroke-linejoin="round"/>',
    }
    body = paths.get(name) or '<circle cx="8" cy="8" r="6"/>'
    return (f'<svg class="ico" viewBox="0 0 16 16" width="15" height="15" aria-hidden="true" '
            f'fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round">'
            f'{body}</svg>')


PAGE_ICON = {"projects": "rocket", "deployments": "rocket", "domains": "globe",
             "traffic": "traffic", "storage": "database", "security": "shield",
             "machine": "chip", "health": "pulse", "plans": "steps"}


def _pip(state):
    return f'<i class="pip" data-state="{state}"></i>' if state else '<i class="pip none"></i>'


def _dot(colour, title=""):
    if _is_colour(colour):
        return f'<i class="dot" style="background:{_e(colour)}" title="{_e(title)}"></i>'
    return ""


def _fact(label, value, mono=True, cls=""):
    c = "figure mono" if mono else "figure"
    return (f'<div class="fact {cls}"><span class="{c}">{_e(value)}</span>'
            f'<span class="label">{_e(label)}</span></div>')


def _bar(pct, state):
    width = max(0, min(100, float(pct or 0)))
    return (f'<div class="bar" data-state="{state}"><span style="width:{width:.0f}%">'
            f'</span></div>')


def _cpu_words(millis):
    try:
        return f"{float(millis) / 1000:g} CPU"
    except (TypeError, ValueError):
        return "?"


def _quantity_words(key, value):
    """A Kubernetes quantity as a person reads it: `2` CPU, `6Gi`, `40`."""
    from . import quantity
    try:
        if key.endswith(".cpu"):
            return _cpu_words(quantity.cpu(value))
        if key.endswith(".memory") or key == "requests.storage":
            return _bytes(quantity.mem(value))
    except (TypeError, ValueError):
        return str(value)
    return str(value)


def _plan_words(numbers):
    """One line for a plan: what it reserves, what it may take."""
    n = numbers or {}
    return (f'{_quantity_words("requests.cpu", n.get("requests.cpu"))} · '
            f'{_quantity_words("requests.memory", n.get("requests.memory"))} reserved · '
            f'up to {_quantity_words("limits.cpu", n.get("limits.cpu"))} · '
            f'{_quantity_words("limits.memory", n.get("limits.memory"))} · '
            f'{n.get("pods", "?")} pods · {n.get("persistentvolumeclaims", "?")} disks · '
            f'{_quantity_words("requests.storage", n.get("requests.storage"))} of disk')


def plans_of(readings):
    """The plans, by name, out of `quota list`'s document."""
    out = {}
    for st in steps_of(reading_for(readings, "quota list")):
        if st.get("step", "").startswith("plan:"):
            out[st["step"].split(":", 1)[1]] = st
    return out


def _note(text, state=None):
    return (f'<p class="note"{f" data-state=\"{state}\"" if state else ""}>{_e(text)}</p>')


# ── reading the readings ─────────────────────────────────────────────
def reading_for(readings, prefix):
    for r in readings or []:
        c = r.get("comando") or ""
        if c == prefix or c.startswith(prefix + " "):
            return r
    return None


def steps_of(reading):
    return ((reading or {}).get("documento") or {}).get("steps") or []


def blind(reading):
    return bool(reading) and (reading.get("sin_documento") or reading.get("documento") is None)


def state_of(step):
    return SCREEN.get((step or {}).get("state"), UNSEEN)


def states_in(reading, steps=None, links=False):
    """Every state a reading carries, at the step level and below.

    THE LINKS OF A PUSH DO NOT DECIDE A VERDICT unless asked for. A
    push the anti-loop skipped has four unmeasured links because
    nothing ran, and on an instance where most pushes only change
    manifests, letting those decide made Deployments read «nobody
    looked» for ever — a signal that never changes is a signal nobody
    reads. Each link keeps its own state on the screen, and the spread
    counts them apart, so nothing is lost by it."""
    out = set()
    if blind(reading):
        return {UNSEEN}
    for st in (steps if steps is not None else steps_of(reading)):
        out.add(state_of(st))
        for m in st.get("measures") or []:
            out.add(state_of(m))
        if links:
            for v in (st.get("links") or {}).values():
                out.add(SCREEN.get(v, UNSEEN))
    return out


def _per_org(readings, key):
    out = {}
    for r in readings or []:
        for st in steps_of(r):
            name = st.get("step", "")
            if name.startswith(key):
                out[name.split(":", 1)[1]] = st
    return out


def window_read(readings):
    for r in readings or []:
        for st in steps_of(r):
            if st.get("step") == "builds" and st.get("leidos"):
                return st["leidos"]
    return None


def org_names(readings):
    return [st.get("step", "").split(":", 1)[1]
            for st in steps_of(reading_for(readings, "org list"))
            if st.get("step", "").startswith("organization:")]


def project_of_image(image, names):
    """Which project an image belongs to. `<org>-<service>` is how a
    tenant's image is named, and the organization's own name is how a
    one-repo tenant's is. The longest match wins, so `shop` does not
    claim `shop-admin-panel`'s images if such a project exists."""
    best = None
    for n in names:
        if image == n or image.startswith(n + "-"):
            if best is None or len(n) > len(best):
                best = n
    return best


def last_push(readings, org, services):
    mine = {sv.get("nombre") for sv in services or []}
    best = None
    for r in readings or []:
        if not (r.get("comando") or "").startswith("builds"):
            continue
        for st in steps_of(r):
            if not st.get("step", "").startswith("build:"):
                continue
            image = st.get("image") or ""
            tail = image[len(org) + 1:] if image.startswith(org + "-") else None
            if image != org and (tail is None or tail not in mine):
                continue
            when = st.get("when") or ""
            if best is None or when > (best.get("when") or ""):
                best = st
    return best


def projects_of(readings, context=None):
    """The projects, assembled ACROSS readings: the contract says which
    exist, the traffic says what reached each one, the builds say what
    happened to its last push, the repositories say what each service
    is written in. `context` is the instance's readings when the
    screen is about one project and the list is not among its own."""
    src = list(readings or []) + list(context or [])
    langs = languages_of(src)
    traffic = _per_org(src, "traffic:")
    window = window_read(src)
    out = []
    for step in steps_of(reading_for(src, "org list")):
        name = step.get("step", "")
        if not name.startswith("organization:"):
            continue
        org = name.split(":", 1)[1]
        services = []
        for sv in step.get("servicios") or []:
            known = langs.get((org, sv.get("nombre"))) or {}
            services.append({
                "name": sv.get("nombre"), "kind": sv.get("tipo"),
                "public": sv.get("publico"), "port": sv.get("puerto"),
                "uses": sv.get("usa") or [], "language": known.get("lenguaje"),
                "colour": known.get("color"), "repo": known.get("repo")})
        out.append({
            "name": org, "state": state_of(step), "valid": step.get("valid", True),
            "error": step.get("error"), "domain": step.get("dominio"),
            "plan": step.get("cuota"), "bucket": bool(step.get("bucket")),
            "ai": step.get("ai"), "contract": step.get("contract"),
            "services": services, "traffic": traffic.get(org),
            "push": last_push(src, org, [{"nombre": s["name"]} for s in services]),
            "window": window})
    return out


def page_states(readings):
    """The dot beside each page in the menu: the worst state among the
    readings that feed it, or nothing when none of them was consulted.
    «Not consulted» is not a state — it is the absence of a reading —
    so it gets no dot rather than a hatched one."""
    out = {}
    check = reading_for(readings, "check")
    for key, _label, _path, feeds in PAGES:
        states = set()
        for prefix in feeds:
            r = reading_for(readings, prefix)
            if r is not None:
                states |= states_in(r)
        if key == "health" and check is not None:
            states |= states_in(check)
        elif key in ROUND_PAGES and check is not None:
            mine = [st for st in steps_of(check) if st.get("step") in ROUND_PAGES[key]]
            if blind(check):
                states.add(UNSEEN)
            else:
                states |= states_in(check, mine)
        out[key] = worst(states) if states else None
    return out


# ── one reading, drawn ───────────────────────────────────────────────
def _section(reading, title, body, states, cls="", lead="", ident="", icon=""):
    """THE ONLY WAY A READING REACHES THE SCREEN. It names its command,
    carries when it was taken, shows its age, and wears the worst of
    the states it holds. Everything a screen draws about a reading goes
    inside one of these — and only one per reading per page."""
    state = worst(states) if states else UNSEEN
    return (f'<section class="source {cls}" data-state="{state}" '
            f'data-command="{_e(reading.get("comando"))}" '
            f'data-rc="{_e(reading.get("rc"))}"{_when(reading)}'
            + (f' id="{_e(ident)}"' if ident else "") + '>'
            f'<header class="src-head">{_icon(icon) if icon else ""}<h2>{_e(title)}</h2>'
            f'{_chip(state, STATE_WORD[state])}{_age(reading)}</header>'
            + (f'<p class="lead">{_e(lead)}</p>' if lead else "")
            + body + '</section>')


def _blind_section(reading, title, cls="", ident="", icon=""):
    """A command that gave back no document. THE CASE ZERO: most
    dashboards answer it with a spinner that never stops, which is a
    promise the page will not keep. Here it is a state with a name and
    the reason travels with it."""
    why = reading.get("sin_documento") or "no document came back"
    body = (f'<p class="why">{_e(why)}</p>'
            f'<p class="note">This is not «nothing is wrong». Nobody could look. '
            f'The command was <code class="mono">aegis {_e(reading.get("comando"))} '
            f'--json</code>.</p>')
    return _section(reading, title, body, {UNSEEN}, cls, ident=ident, icon=icon)


def _measure(m):
    state = state_of(m)
    notes = "".join(f'<p class="note">{_e(n)}</p>' for n in m.get("notes") or [])
    return (f'<li class="measure" data-state="{state}">{_chip(state, STATE_WORD[state])}'
            f'<span class="what">{_e(m.get("measure", ""))}</span>{notes}</li>')


def _step(step):
    """One step of a document, generically: its state, its measures,
    and every other field the producer attached, shown rather than
    dropped. It is how a surplus CNAME reaches the screen without
    anybody inventing a state for it."""
    state = state_of(step)
    measures = step.get("measures") or []
    inner = f'<ul class="measures">{"".join(_measure(m) for m in measures)}</ul>' if measures else ""
    extra = {k: v for k, v in step.items()
             if k not in ("step", "state", "measures", "notes", "counts")}
    facts = "".join(f'<dt>{_e(k)}</dt><dd>{_e(v)}</dd>' for k, v in extra.items())
    facts = f'<dl class="facts">{facts}</dl>' if facts else ""
    return (f'<article class="step" data-state="{state}" data-step="{_e(step.get("step", "?"))}">'
            f'<h3>{_e(step.get("step", "?"))}</h3>{_chip(state, STATE_WORD[state])}'
            f'{facts}{inner}</article>')


def _dump(reading, title=None, cls="", icon=""):
    """The generic drawing: every step, every measure, every fact,
    nothing lost. It is what a command nobody has designed a screen for
    gets, and it stays underneath every designed screen as the floor."""
    if blind(reading):
        return _blind_section(reading, title or reading.get("comando"), cls, icon=icon)
    steps = steps_of(reading)
    states = states_in(reading)
    body = "".join(_step(st) for st in steps)
    if not steps:
        states.add(UNSEEN)
        body = f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>'
    return _section(reading, title or reading.get("comando"), body, states, cls, icon=icon)


def _round_subset(reading, page, more_href="/health"):
    """The round's sections that belong to a page, and a COUNT of the
    rest with the worst of their states — so that a screen showing five
    of fourteen sections never reads as if the other nine were fine."""
    if reading is None:
        return ""
    if blind(reading):
        return _blind_section(reading, "The round", "round", icon="pulse")
    names = ROUND_PAGES.get(page, ())
    mine = [st for st in steps_of(reading) if st.get("step") in names]
    rest = [st for st in steps_of(reading) if st.get("step") not in names]
    states = states_in(reading, mine)
    body = _round_list(mine)
    if rest:
        rs = worst(states_in(reading, rest))
        body += (f'<p class="more"><a href="{_e(more_href)}">{_pip(rs)}{len(rest)} more '
                 f'section{"s" if len(rest) != 1 else ""} of the round on Health</a></p>')
    if not mine:
        states.add(UNSEEN)
        body = (f'<p class="empty" data-state="{UNSEEN}">the round has no section about '
                f'this today</p>') + body
    return _section(reading, "What the round says about it", body, states, "round",
                    icon="pulse")


def _round_list(steps, all_open=False):
    """The sections of the round as a status list, worst first. A
    section that is fine is one line; one that is not opens itself with
    only the measures that are not fine, and the fine ones are COUNTED
    so the fold never reads as «there was nothing else»."""
    rows = []
    order = {UNSEEN: 0, WRONG: 1, ATTENTION: 2, BUSY: 3, FINE: 4}
    for st in sorted(steps, key=lambda s: (order.get(state_of(s), 9), s.get("step", ""))):
        state = state_of(st)
        shown, hidden = [], 0
        for m in st.get("measures") or []:
            ms = state_of(m)
            if ms == FINE and not all_open:
                hidden += 1
                continue
            notes = "".join(f'<p class="note">{_e(n)}</p>' for n in m.get("notes") or [])
            shown.append(f'<li class="measure" data-state="{ms}">{_chip(ms, STATE_WORD[ms])}'
                         f'<span class="what">{_e(m.get("measure", ""))}</span>{notes}</li>')
        body = ""
        if shown:
            body = f'<ul class="measures">{"".join(shown)}</ul>'
        if hidden:
            body += f'<p class="rest">{hidden} measure{"s" if hidden != 1 else ""}, all fine</p>'
        opened = " open" if state != FINE else ""
        rows.append(
            f'<details class="sect" data-state="{state}" data-step="{_e(st.get("step", ""))}"{opened}>'
            f'<summary>{_pip(state)}<b>{_e(st.get("step", "?"))}</b>'
            f'<span class="count">{len(st.get("measures") or [])} measured</span></summary>'
            f'{body}</details>')
    if not rows:
        return f'<p class="empty" data-state="{UNSEEN}">the round measured nothing</p>'
    return f'<div class="sects">{"".join(rows)}</div>'


# ── the frame ────────────────────────────────────────────────────────
def _oldest(readings):
    whens = [r.get("medido_en") for r in readings or [] if r.get("medido_en")]
    return min(whens) if whens else None


def frame(main, readings, active, subject=None):
    """The chrome around every screen: the menu with a dot per page,
    when the instance was read, and the one way to read it again. It
    is the same on every page so that a person always knows where they
    are — which is most of what a console is for."""
    dots = page_states(readings)
    by = {k: (label, path) for k, label, path, _f in PAGES}
    items = []
    for group, keys in MENU:
        items.append(f'<h4>{_e(group)}</h4>')
        for key in keys:
            label, path = by[key]
            here = ' class="here"' if key == active else ""
            items.append(f'<a href="{path}"{here}>{_icon(PAGE_ICON[key])}<span>{_e(label)}</span>'
                         f'{_pip(dots.get(key))}</a>')
    when = _oldest(readings)
    read = (f'instance read {_e(_time(when))}' if when else "instance not read yet")
    return (f'<div class="console">'
            f'<aside class="side"><a class="brand" href="/">aegis</a>'
            f'<nav class="menu">{"".join(items)}</nav>'
            f'<div class="side-foot"><p class="measured">{read}</p>'
            f'<a class="act act--quiet" href="/measure">Read it again</a></div></aside>'
            f'{main}</div>')


def _wheres(readings):
    """The pages that are not fine, as links beside the sentence: the
    sentence says something is wrong, this says where to click."""
    dots = page_states(readings)
    by = {k: (label, path) for k, label, path, _f in PAGES}
    bad = [(k, dots[k]) for k, _l, _p, _f in PAGES if dots.get(k) and dots[k] != FINE]
    if not bad:
        return ""
    return ('<p class="wheres">' + "".join(
        f'<a href="{by[k][1]}">{_pip(st)}{_e(by[k][0])}</a>' for k, st in bad) + '</p>')


def _top(crumbs, verdict, sentence=None, actions="", wheres=""):
    trail = []
    for i, (label, href) in enumerate(crumbs):
        if href and i < len(crumbs) - 1:
            trail.append(f'<a href="{_e(href)}">{_e(label)}</a>')
        else:
            trail.append(f'<b>{_e(label)}</b>')
    return (f'<header class="top" data-state="{verdict}">'
            f'<p class="crumbs">{"<span>/</span>".join(trail)}</p>'
            f'<p class="sentence">{_e(sentence or SENTENCE[verdict])}</p>{wheres}'
            + (f'<div class="actions">{actions}</div>' if actions else "") + '</header>')


def _main(view, verdict, crumbs, body, actions="", sentence=None, subject=None, wheres=""):
    return (f'<main class="sereno screen" data-veredicto="{verdict}" data-view="{_e(view)}"'
            + (f' data-subject="{_e(subject)}"' if subject else "")
            + f'>{_top(crumbs, verdict, sentence, actions, wheres)}'
            + (f'<p class="lead page-lead">{_e(LEAD[view])}</p>' if view in LEAD else "")
            + body + '</main>')


# ── the projects (overview) ──────────────────────────────────────────
def _chain(links, small=False):
    return (f'<span class="chain{" small" if small else ""}">'
            + "".join(f'<span class="link" data-state="{SCREEN.get(v, UNSEEN)}" title="{_e(k)}">'
                      f'{_e(LINK_WORD.get(k, k))}</span>' for k, v in (links or {}).items())
            + '</span>')


def _service_pill(sv):
    icon = _icon(KIND_ICON.get(sv.get("kind"), "web"))
    lang = sv.get("language")
    return (f'<span class="pill" title="{_e(KIND.get(sv.get("kind"), sv.get("kind")))}">'
            f'{icon}{_e(sv.get("name"))}'
            + (f'<i>{_dot(sv.get("colour"), lang)}{_e(lang)}</i>' if lang else
               f'<i>{_e(KIND.get(sv.get("kind"), sv.get("kind")))}</i>')
            + '</span>')


def _project_card(p):
    name = p["name"]
    if not p["valid"]:
        return (f'<article class="card proj" data-state="{p["state"]}">'
                f'<h3><a href="/projects/{_e(name)}">{_e(name)}</a></h3>'
                f'{_chip(p["state"], "contract refused")}'
                f'<p class="why">{_e(p.get("error") or "")}</p></article>')
    pills = "".join(_service_pill(sv) for sv in p["services"])
    figs = ""
    t = p.get("traffic")
    if t and "requests" in t:
        figs = (f'<div class="facts-row">{_fact("requests · 24h", _num(t.get("requests", 0)))}'
                f'{_fact("errors", _num(t.get("errors", 0)))}'
                f'{_fact("p95", "%.0f ms" % float(t.get("p95_ms") or 0))}</div>')
    push = p.get("push")
    if push:
        deploy = (f'<p class="push"><span class="lbl">last deployment</span>'
                  f'<span class="mono">{_e(push.get("image"))} #{_e(push.get("build"))}</span>'
                  f'<span class="when">{_e(_time(push.get("when")))}</span>'
                  f'{_chain(push.get("links"), small=True)}'
                  + (f'<span class="why">{_e(push["why"])}</span>' if push.get("why") else "")
                  + '</p>')
    elif p.get("window"):
        deploy = f'<p class="push none">no deployment among the last {_e(p["window"])} read</p>'
    else:
        deploy = ""
    state = worst({p["state"], state_of(push)} if push else {p["state"]})
    extras = [f'plan <b class="mono">{_e(p["plan"])}</b>']
    if p["bucket"]:
        extras.append("bucket")
    if p["ai"]:
        extras.append(f'AI {_e(p["ai"])}')
    domain = (f'<a class="host mono" href="https://{_e(p["domain"])}/" rel="noreferrer">'
              f'{_e(p["domain"])}</a>' if p["domain"] else
              '<span class="host mono faint">no public domain</span>')
    return (f'<article class="card proj" data-state="{state}">'
            f'<header><h3><a href="/projects/{_e(name)}">{_e(name)}</a></h3>'
            f'{_chip(state, STATE_WORD[state])}</header>'
            f'{domain}<div class="pills">{pills}</div>{figs}{deploy}'
            f'<p class="meta">{" · ".join(extras)} · {len(p["services"])} service'
            f'{"s" if len(p["services"]) != 1 else ""}</p></article>')


def _spread(reading):
    """How many things of the reading are in each state, worst first.
    A summary that showed only the worst state would flatten every
    other one out of the screen; this is what keeps a peek honest
    (check 122 found the first version doing exactly that)."""
    counts, links = {}, {}
    if blind(reading):
        counts[UNSEEN] = 1
    for st in steps_of(reading):
        counts[state_of(st)] = counts.get(state_of(st), 0) + 1
        for m in st.get("measures") or []:
            counts[state_of(m)] = counts.get(state_of(m), 0) + 1
        for v in (st.get("links") or {}).values():
            k = SCREEN.get(v, UNSEEN)
            links[k] = links.get(k, 0) + 1
    order = {UNSEEN: 0, WRONG: 1, ATTENTION: 2, BUSY: 3, FINE: 4}
    def spots(d, what):
        return "".join(f'<span class="spot" title="{n} {what} {STATE_WORD[k]}">{_pip(k)}<b>{n}</b></span>'
                       for k, n in sorted(d.items(), key=lambda kv: order.get(kv[0], 9)))
    out = spots(counts, "")
    if links:
        # The links of every push, counted apart from the pushes: a
        # hatched count here is links nobody measured, most often
        # because nothing was built.
        out += f'<span class="spot lbl">links</span>' + spots(links, "links")
    return out


def _round_line(readings, key):
    """What the round adds to a page's dot, said on the page's peek so
    that a red dot in the menu beside a peek that looks fine is not a
    riddle: the peek is one reading, the dot is every reading that
    feeds the page."""
    check = reading_for(readings, "check")
    if check is None or key not in ROUND_PAGES:
        return ""
    if blind(check):
        return f'<span class="round">{_pip(UNSEEN)}the round could not look</span>'
    mine = [st for st in steps_of(check) if st.get("step") in ROUND_PAGES[key]]
    if not mine:
        return ""
    st = worst(states_in(check, mine))
    bad = [x.get("step") for x in mine if state_of(x) != FINE]
    if bad:
        return (f'<span class="round">{_pip(st)}round: {_e(", ".join(bad))}</span>')
    return f'<span class="round">{_pip(st)}round: {len(mine)} fine</span>'


def _peek(reading, key, label, path, figure, states, extra=""):
    """One page, summarised on the overview in a line, a number and the
    spread of its states, and drawn as the SECTION of the reading that
    feeds it: it is that reading's one appearance on this screen, so it
    carries the command, the time and the age like any other."""
    state = worst(states) if states else UNSEEN
    return (f'<section class="source peek" data-state="{state}" '
            f'data-command="{_e(reading.get("comando"))}" '
            f'data-rc="{_e(reading.get("rc"))}"{_when(reading)}>'
            f'<a class="cover" href="{path}">{_icon(PAGE_ICON[key])}<b>{_e(label)}</b>'
            f'<span class="fig">{_e(figure)}</span><span class="spread">{_spread(reading)}'
            f'</span>{extra}</a>{_age(reading)}</section>')


def _peek_figure(key, reading):
    steps = steps_of(reading)
    if key == "health":
        bad = sum(1 for st in steps if state_of(st) != FINE)
        return f'{len(steps)} sections' + (f' · {bad} not fine' if bad else " · all fine")
    if key == "deployments":
        pushes = [st for st in steps if st.get("step", "").startswith("build:")]
        built = sum(1 for st in pushes if (st.get("links") or {}).get("build") == "done")
        bad = sum(1 for st in pushes if state_of(st) != FINE)
        return (f'{len(pushes)} pushes · {built} built'
                + (f' · {bad} not fine' if bad else ""))
    if key == "domains":
        n = next((st.get("hostnames") for st in steps if st.get("step") == "edge"), None)
        missing = sum(1 for st in steps if st.get("step", "").startswith("hostname:"))
        surplus = next((st.get("count") for st in steps if st.get("step") == "surplus-cnames"), 0)
        out = f'{n} at the edge' if n is not None else f'{len(steps)} readings'
        if missing:
            out += f' · {missing} missing'
        if surplus:
            out += f' · {surplus} surplus'
        return out
    if key == "traffic":
        total = next((st for st in steps if st.get("step") == "traffic:total"), None)
        errors = sum(int(st.get("errors", 0)) for st in steps if "errors" in st)
        if total:
            return f'{_num(total.get("requests", 0))} requests · {total.get("hours", 24)}h' + (
                f' · {_num(errors)} errors' if errors else "")
        return f'{len(steps)} readings'
    if key == "storage":
        copies = [st for st in steps if st.get("step", "").startswith("backup:")]
        holding = [st for st in copies if st.get("holds")]
        ages = [st.get("age_hours") for st in holding if st.get("age_hours") is not None]
        out = f'{len(holding)} with data'
        if ages:
            out += f' · copy {max(ages):g} h old' if len(ages) == 1 else \
                   f' · oldest copy {max(ages):g} h'
        return out
    if key == "machine":
        mem = next((st.get("free") for st in steps if st.get("step") == "capacity:memory"), None)
        fits = [st for st in steps if st.get("step", "").startswith("fits:")]
        room = max((st.get("room") or 0) for st in fits) if fits else None
        out = f'{_bytes(mem)} free' if mem is not None else f'{len(steps)} readings'
        if room is not None:
            out += f' · fits {room} more'
        return out
    if key == "plans":
        plans = [st for st in steps if st.get("step", "").startswith("plan:")]
        mine = sum(1 for st in plans if not st.get("de_serie"))
        return (f'{len(plans)} plans' + (f' · {mine} yours' if mine else " · all shipped"))
    return f'{len(steps)} readings'


def import_box(reading, href="/new"):
    """The repositories NOTHING is running yet, as the way in to a new
    project. Vercel calls this «Import Git Repository», and it is the
    one list somebody needs in front of them to take a repository on."""
    if blind(reading):
        return _blind_section(reading, "Import a repository", "import", icon="rocket")
    steps = steps_of(reading)
    states = states_in(reading)
    total = deployed = 0
    free = []
    for st in steps:
        if st.get("step") == "repos":
            total, deployed = st.get("total", 0), st.get("deployed", 0)
        elif st.get("step", "").startswith("repo:") and not st.get("sirve"):
            free.append((st.get("empujado") or "", st.get("step").split(":", 1)[1],
                         st.get("lenguaje"), st.get("color")))
    free.sort(reverse=True)
    shown = free[:6]
    rows = "".join(
        f'<li><a class="repo" href="{href}?repo={_e(name)}">{_icon("static")}'
        f'<span class="mono">{_e(name)}</span>'
        + (f'<i>{_dot(colour, lang)}{_e(lang)}</i>' if lang else "")
        + f'<span class="when">{_e(_time(when))}</span>'
        f'<span class="act act--quiet small">Import</span></a></li>'
        for when, name, lang, colour in shown)
    rest = (f'<li class="rest"><a href="{href}">and {len(free) - len(shown)} more that nothing '
            f'is running</a></li>' if len(free) > len(shown) else "")
    if not steps:
        states.add(UNSEEN)
        body = (f'<p class="empty" data-state="{UNSEEN}">GitHub could not be asked, which '
                f'is not the same as having no repositories</p>')
    else:
        body = (f'<div class="facts-row">{_fact("repositories", _num(total))}'
                f'{_fact("deployed here", _num(deployed))}'
                f'{_fact("could be", _num(len(free)))}</div>'
                f'<ul class="repos">{rows}{rest}</ul>')
    return _section(reading, "Import a repository", body, states, "import",
                    lead="Your repositories on GitHub that no project runs yet. Picking one "
                         "opens the new-project form already filled with what was measured "
                         "about it.", icon="rocket")


def overview(readings):
    """THE FIRST SCREEN: your projects, and one line per page of the
    console with its state — so the whole instance is read in a glance
    and the detail is one click away, never a scroll."""
    v = verdict_of(readings)
    peeks, drawn = [], set()
    order = ("deployments", "domains", "traffic", "storage", "plans", "machine", "health")
    labels = {k: (lbl, path) for k, lbl, path, _f in PAGES}
    feeds = {k: f for k, _l, _p, f in PAGES}
    for key in order:
        for prefix in feeds[key]:
            r = reading_for(readings, prefix)
            if r is None or id(r) in drawn:
                continue
            drawn.add(id(r))
            label, path = labels[key]
            extra = _round_line(readings, key)
            if blind(r):
                peeks.append(_peek(r, key, label, path, "could not look", {UNSEEN}, extra))
                continue
            st = states_in(r)
            if not steps_of(r):
                st.add(UNSEEN)
            peeks.append(_peek(r, key, label, path, _peek_figure(key, r), st, extra))
    org = reading_for(readings, "org list")
    projects = ""
    if org is not None:
        drawn.add(id(org))
        if blind(org):
            projects = _blind_section(org, "Projects", "projects", icon="rocket")
        else:
            ps = projects_of(readings)
            states = states_in(org)
            cards = "".join(_project_card(p) for p in ps)
            if not ps and steps_of(org):
                # Contracts were read and none is a project: the honest
                # empty state, with the two ways in.
                cards = ('<div class="empty-state"><p>No projects yet. A project is one of '
                         'your applications, described in one file the platform derives '
                         'everything from.</p><p><a class="act" href="/new">Import a '
                         'repository</a> <a class="act act--quiet" href="/new">Describe one '
                         'by hand</a></p></div>')
            elif not ps:
                states.add(UNSEEN)
                cards = f'<p class="empty" data-state="{UNSEEN}">no contract was read</p>'
            projects = _section(org, f"Your projects · {len(ps)}" if ps else "Your projects",
                                f'<div class="grid">{cards}</div>', states,
                                "projects", icon="rocket")
    repos = reading_for(readings, "repos list")
    imports = ""
    if repos is not None:
        drawn.add(id(repos))
        imports = import_box(repos)
    # Anything else that was consulted and has no place designed for it
    # is drawn in full: a reading may never vanish because nobody has
    # designed its screen yet.
    others = "".join(_dump(r) for r in readings if id(r) not in drawn)
    body = ((f'<div class="strip">{"".join(peeks)}</div>' if peeks else "")
            + projects + imports + others)
    actions = '<a class="act" href="/new">New project</a>'
    return _main("projects", v, [("Projects", "/")], body, actions, wheres=_wheres(readings))


# ── one project ──────────────────────────────────────────────────────
def _service_card(st, lang=None):
    kind, _, what = st.get("step", "").partition(":")
    state = state_of(st)
    ready, desired = st.get("ready"), st.get("desired")
    count = f'{ready} of {desired} running' if desired is not None else "nothing running"
    tipo = st.get("tipo")
    bits = [f'<span class="pill">{_icon(KIND_ICON.get(tipo, "web"))}'
            f'{_e(KIND.get(tipo, tipo or "?"))}</span>']
    if lang and lang.get("lenguaje"):
        bits.append(f'<span class="pill">{_dot(lang.get("color"), lang["lenguaje"])}'
                    f'{_e(lang["lenguaje"])}</span>')
    if st.get("publico"):
        bits.append(f'<span class="pill mono">{_e(st["publico"])}</span>')
    if st.get("volume"):
        bits.append(f'<span class="pill">{_icon("database")}{_e(st.get("volume_size") or "disk")}'
                    f'<i>{_e(st.get("volume_phase", ""))}</i></span>')
    elif st.get("volume_phase") == "missing":
        bits.append(f'<span class="pill">{_chip(WRONG, "no disk")}</span>')
    elif st.get("volume_unmeasured"):
        bits.append(f'<span class="pill">{_chip(UNSEEN, "disk not measured")}</span>')
    why = st.get("why")
    return (f'<article class="card svc" data-state="{state}">'
            f'<header><h3>{_e(what)}</h3>{_chip(state, count)}</header>'
            f'<div class="pills">{"".join(bits)}</div>'
            + (f'<p class="why">{_e(WHY.get(why, why))}</p>' if why else "")
            + (f'<p class="meta mono" title="{_e(st.get("digest"))}">runs {_e(st["digest"][:19])}…</p>'
               if st.get("digest") else "")
            + '</article>')


def _tenant_section(reading, langs, org):
    if blind(reading):
        return _blind_section(reading, "Services", "services", ident="services",
                              icon="rocket")
    steps = steps_of(reading)
    states = states_in(reading)
    cards, routes, facts, extra = [], [], [], []
    quota = ""
    for st in steps:
        kind, _, what = st.get("step", "").partition(":")
        state = state_of(st)
        if kind == "namespace":
            facts.append(_fact("namespace", st.get("namespace", "?")))
            if not st.get("exists"):
                extra.append(f'<li>{_chip(state, "namespace")}<span class="note">the contract '
                             f'is in git and nothing of it is running</span></li>')
        elif kind == "service":
            cards.append(_service_card(st, langs.get((org, what))))
        elif kind == "public":
            eps = st.get("endpoints")
            note = ("not routed" if not st.get("routed") else
                    "routed, and nobody is behind it" if eps == 0 else
                    "routed; nobody counted who is behind it" if eps is None else
                    f'routed to {eps} running cop{"y" if eps == 1 else "ies"}')
            routes.append(f'<tr><td class="mono">{_e(st.get("publico", "/"))}</td>'
                          f'<td>{_e(what)}</td><td class="mono faint">{_e(st.get("service", ""))}</td>'
                          f'<td>{_chip(state, STATE_WORD[state])}</td><td class="note">{_e(note)}</td></tr>')
        elif kind == "routing":
            for host in st.get("hosts") or []:
                facts.append(_fact("hostname", host))
        elif kind == "quota":
            pct = st.get("percent")
            if pct is None:
                extra.append(f'<li>{_chip(state, "usage")}<span class="note">'
                             f'{_e(st.get("why", "not measured"))}</span></li>')
            else:
                tight = st.get("tightest", "")
                used = (st.get("used") or {}).get(tight)
                hard = (st.get("hard") or {}).get(tight)
                quota = (f'<div class="usage"><div class="fact quota"><span class="figure">'
                         f'{pct:.0f}%</span><span class="label">of the plan\'s '
                         f'{_e(QUOTA_WORD.get(tight, tight))}, the tightest</span>'
                         f'{_bar(pct, state)}<span class="label mono">{_e(used)} of {_e(hard)}'
                         f'</span></div>'
                         + "".join(_fact(QUOTA_WORD.get(k, k),
                                         f'{(st.get("used") or {}).get(k, "?")} of {v}')
                                   for k, v in (st.get("hard") or {}).items() if k != tight)
                         + '</div>')
        else:
            extra.append(f'<li>{_chip(state, kind)}<span class="mono">{_e(what)}</span>'
                         f'<span class="note">{_e(WHY.get(kind, kind))}</span></li>')
    if not cards and not extra:
        states.add(UNSEEN)
        cards.append(f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>')
    body = ((f'<div class="facts-row head">{"".join(facts)}</div>' if facts else "")
            + f'<div class="grid">{"".join(cards)}</div>'
            + (f'<h3 class="sub" id="routes">Routes</h3><table class="rows"><thead><tr>'
               f'<th>path</th><th>service</th><th>answers as</th><th></th><th></th></tr></thead>'
               f'<tbody>{"".join(routes)}</tbody></table>' if routes else "")
            + (f'<h3 class="sub" id="usage">Usage</h3>{quota}' if quota else "")
            + (f'<h3 class="sub" id="unclaimed">Not in the contract</h3><ul class="tail">'
               f'{"".join(extra)}</ul>' if extra else ""))
    return _section(reading, "Services", body, states, "services", ident="services",
                    lead="What the contract declares, against what is actually running "
                         "in this project's namespace.", icon="rocket")


def _deploy_rows(reading, names, with_project=True):
    rows, gaps = [], []
    steps = sorted((st for st in steps_of(reading) if st.get("step", "").startswith("build:")),
                   key=lambda s: s.get("when") or "", reverse=True)
    for st in steps:
        state = state_of(st)
        image = st.get("image", "?")
        proj = project_of_image(image, names) if with_project else None
        rows.append(
            f'<tr>' + (f'<td><a href="/projects/{_e(proj)}">{_e(proj)}</a></td>' if with_project and proj
                       else ('<td class="faint">?</td>' if with_project else ""))
            + f'<td class="mono">{_e(image)}</td><td class="mono">#{_e(st.get("build", "?"))}</td>'
            f'<td class="mono faint">{_e(st.get("branch", ""))}</td>'
            f'<td class="when">{_e(_time(st.get("when")))}</td>'
            f'<td>{_chain(st.get("links"))}</td>'
            f'<td>{_pip(state)}</td>'
            f'<td class="note">{_e(st.get("why") or "")}</td></tr>')
    for st in steps_of(reading):
        if st.get("step") == "builds" and st.get("links_elsewhere"):
            for link, who in (st["links_elsewhere"] or {}).items():
                gaps.append(f'<li>{_chip(UNSEEN, link)}<span class="note">not measured here: '
                            f'{_e(who)}</span></li>')
    return rows, gaps


def _builds_section(reading, names, with_project=True, ident="deployments"):
    if blind(reading):
        return _blind_section(reading, "Deployments", "deploys", ident=ident, icon="rocket")
    states = states_in(reading)
    rows, gaps = _deploy_rows(reading, names, with_project)
    if not rows:
        states.add(UNSEEN)
        table = f'<p class="empty" data-state="{UNSEEN}">no build was read</p>'
    else:
        table = (f'<table class="rows deploys"><thead><tr>'
                 + ('<th>project</th>' if with_project else "")
                 + '<th>image</th><th>build</th><th>branch</th><th>when</th>'
                 '<th>built · scanned · signed · pinned</th><th></th><th></th></tr></thead>'
                 f'<tbody>{"".join(rows)}</tbody></table>')
    pushes = [st for st in steps_of(reading) if st.get("step", "").startswith("build:")]
    built = sum(1 for st in pushes if (st.get("links") or {}).get("build") == "done")
    skipped = sum(1 for st in pushes if st.get("why"))
    failed = sum(1 for st in pushes if state_of(st) == WRONG)
    summary = (f'<div class="facts-row head">{_fact("pushes read", _num(len(pushes)))}'
               f'{_fact("built", _num(built))}{_fact("nothing to build", _num(skipped))}'
               + (_fact("failed", _num(failed)) if failed else "") + '</div>') if pushes else ""
    legend = ('<p class="note legend">A push is <b>built</b> into an image, <b>scanned</b> '
              'for known vulnerabilities, <b>signed</b> so the cluster can refuse anything '
              'else, and <b>pinned</b> by digest so what runs is exactly what was signed. '
              'A hatched link is one nobody measured.</p>')
    body = summary + table + (f'<ul class="tail">{"".join(gaps)}</ul>' if gaps else "") + legend
    window = window_read([reading])
    lead = (f'The last {window} pushes read, newest first.' if window else
            'The pushes read, newest first.')
    return _section(reading, "Deployments", body, states, "deploys", lead=lead, ident=ident,
                    icon="rocket")


def _traffic_rows(reading, names=None):
    rows, tail = [], []
    steps = steps_of(reading)
    top = max((int(st.get("requests", 0)) for st in steps if "requests" in st), default=0)
    for st in steps:
        state = state_of(st)
        name = st.get("step", "").split(":", 1)[-1]
        if name in ("platform", "unattributed", "total") or "errors" not in st:
            tail.append(f'<tr class="tail-row"><td>{_e(name)}</td>'
                        f'<td class="mono num">{_e(_num(st.get("requests", 0)))}</td>'
                        f'<td colspan="4" class="note">{_e(st.get("note") or "")}</td>'
                        f'<td>{_pip(state)}</td></tr>')
            continue
        req = int(st.get("requests", 0))
        pct = (req / top * 100) if top else 0
        who = (f'<a href="/projects/{_e(name)}">{_e(name)}</a>'
               if names is None or name in names else _e(name))
        rows.append(f'<tr><td>{who}</td>'
                    f'<td class="mono num">{_e(_num(req))}</td>'
                    f'<td class="bar-cell">{_bar(pct, state)}</td>'
                    f'<td class="mono num">{_e(_num(st.get("errors", 0)))}</td>'
                    f'<td class="mono num">{st.get("p95_ms", 0):.0f} ms</td>'
                    f'<td class="mono num">{_e(_bytes(st.get("bytes", 0)))}</td>'
                    f'<td>{_pip(state)}</td></tr>')
    return rows, tail


def _traffic_section(reading, names=None, ident="traffic"):
    if blind(reading):
        return _blind_section(reading, "Traffic", "traffic", ident=ident, icon="traffic")
    states = states_in(reading)
    rows, tail = _traffic_rows(reading, names)
    hours = next((st.get("hours") for st in steps_of(reading) if st.get("hours")), 24)
    if not rows and not tail:
        states.add(UNSEEN)
        body = f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>'
    else:
        body = (f'<table class="rows traffic"><thead><tr><th>project</th><th class="num">requests</th>'
                f'<th></th><th class="num">errors (5xx)</th><th class="num">p95</th>'
                f'<th class="num">served</th><th></th></tr></thead>'
                f'<tbody>{"".join(rows)}{"".join(tail)}</tbody></table>')
    return _section(reading, "Traffic", body, states, "traffic", ident=ident,
                    lead=f"The last {hours} hours, as the edge counted them.", icon="traffic")


def _backup_rows(reading, names=None):
    rows = []
    for st in steps_of(reading):
        if not st.get("step", "").startswith("backup:"):
            continue
        state = state_of(st)
        org = st.get("step").split(":", 1)[1]
        who = (f'<a href="/projects/{_e(org)}">{_e(org)}</a>'
               if names is None or org in names else _e(org))
        holds = "".join(f'<span class="pill">{_icon(KIND_ICON.get(d.get("tipo"), "database"))}'
                        f'{_e(d.get("servicio"))}</span>' for d in st.get("databases") or [])
        if st.get("bucket"):
            holds += f'<span class="pill">{_icon("bucket")}bucket</span>'
        age = st.get("age_hours")
        cad = st.get("cadence_seconds") or 0
        note = st.get("note") or WHY_BACKUP.get(st.get("why"), st.get("why")) or ""
        if st.get("late"):
            note = "later than two turns of its own clock"
        rows.append(f'<tr><td>{who}</td><td><div class="pills">{holds or "<span class=faint>none</span>"}</div></td>'
                    f'<td class="mono num">{f"{age:g} h" if age is not None else "?"}</td>'
                    f'<td class="mono num">{f"every {cad // 3600} h" if cad else "?"}</td>'
                    f'<td class="mono num">{_e(st.get("copies", 0))}</td>'
                    f'<td class="mono num">{_e(_bytes(st.get("bytes", 0))) if st.get("bytes") else ""}</td>'
                    f'<td>{_chip(state, STATE_WORD[state])}</td><td class="note">{_e(note)}</td></tr>')
    return rows


def _backup_section(reading, names=None, ident="storage"):
    if blind(reading):
        return _blind_section(reading, "Off-site copies", "backups", ident=ident,
                              icon="database")
    states = states_in(reading)
    rows = _backup_rows(reading, names)
    if not rows:
        states.add(UNSEEN)
        body = f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>'
    else:
        body = (f'<table class="rows backups"><thead><tr><th>project</th><th>holds</th>'
                f'<th class="num">newest copy</th><th class="num">clock</th>'
                f'<th class="num">copies</th><th class="num">size</th><th></th><th></th>'
                f'</tr></thead><tbody>{"".join(rows)}</tbody></table>')
    return _section(reading, "Off-site copies", body, states, "backups", ident=ident,
                    lead="Every project that holds data is bundled, encrypted and sent to the "
                         "destination on a clock. «Newest copy» is read against that clock: "
                         "one missed turn is a machine that was off, two is a mechanism that "
                         "stopped.", icon="database")


def _settings(p, org, plans=None):
    """The contract, as a person reads it. Not a reading of its own —
    it is the same `org list` step the projects screen drew — so it is
    a plain block that says where it came from, with the one button
    that opens the editor."""
    if p is None:
        return (f'<section class="block" id="settings"><header class="src-head">'
                f'{_icon("static")}<h2>Settings</h2></header>'
                f'<p class="empty">the contract of {_e(org)} was not read on this page</p>'
                f'</section>')
    rows = "".join(
        f'<tr><td>{_service_pill(sv)}</td><td>{_e(KIND.get(sv["kind"], sv["kind"]))}</td>'
        f'<td class="mono">{_e(sv["public"] or "")}</td><td class="mono">{_e(sv["port"] or "")}</td>'
        f'<td>{_e(", ".join(USES.get(u, u) for u in sv["uses"]) or "nothing")}</td></tr>'
        for sv in p["services"])
    plan = (plans or {}).get(p["plan"]) or {}
    about_plan = ""
    if plan:
        about_plan = (f'<p class="note">Plan <b class="mono">{_e(p["plan"])}</b>'
                      + (f': {_e(plan["descripcion"])}' if plan.get("descripcion") else "")
                      + f' · {_e(_plan_words(plan.get("numeros")))} · '
                      f'<a href="/plans">every plan</a></p>')
    facts = (f'<div class="facts-row head">{_fact("plan", p["plan"] or "?")}'
             f'{_fact("domain", p["domain"] or "none")}'
             f'{_fact("contract", p["contract"] or "?")}'
             + (_fact("bucket", "yes") if p["bucket"] else "")
             + (_fact("AI plan", p["ai"]) if p["ai"] else "") + '</div>')
    return (f'<section class="block" id="settings"><header class="src-head">{_icon("static")}'
            f'<h2>Settings</h2><a class="act" href="/projects/{_e(org)}/edit">Edit the contract</a>'
            f'</header><p class="lead">The contract is the one file in git that says what this '
            f'project is. Everything the platform derives —manifests, policies, quota— comes '
            f'from it, and editing it here writes that file and nothing else.</p>{facts}{about_plan}'
            f'<table class="rows"><thead><tr><th>service</th><th>kind</th><th>public path</th>'
            f'<th>port</th><th>may reach</th></tr></thead><tbody>{rows}</tbody></table>'
            f'</section>')


def project(readings, subject, instance=None):
    """ONE PROJECT. Its readings are scoped at the command —`tenant show
    <name>`, `builds show --org <name>`— and never filtered here, so the
    verdict at the top is about this project and nothing else. The
    instance's readings are context: the contract, the languages, the
    menu's dots."""
    v = verdict_of(readings)
    ctx = list(instance or [])
    langs = languages_of(ctx + list(readings))
    p = next((x for x in projects_of([], ctx) if x["name"] == subject), None)
    names = org_names(ctx) or [subject]
    drawn, parts = set(), {}
    tenant = reading_for(readings, "tenant show")
    if tenant is not None:
        drawn.add(id(tenant))
        parts["services"] = _tenant_section(tenant, langs, subject)
    builds = reading_for(readings, "builds show")
    if builds is not None:
        drawn.add(id(builds))
        parts["deployments"] = _builds_section(builds, names, with_project=False)
    traffic = reading_for(readings, "traffic show")
    if traffic is not None:
        drawn.add(id(traffic))
        parts["traffic"] = _traffic_section(traffic, names)
    backup = reading_for(readings, "data remote status")
    if backup is not None:
        drawn.add(id(backup))
        parts["storage"] = _backup_section(backup, names)
    others = "".join(_dump(r) for r in readings if id(r) not in drawn)
    tabs = [("services", "Services"), ("deployments", "Deployments"), ("traffic", "Traffic"),
            ("storage", "Storage"), ("settings", "Settings")]
    strip = ('<nav class="tabs">'
             + "".join(f'<a href="#{k}">{_e(l)}</a>' for k, l in tabs if k in parts or k == "settings")
             + '</nav>')
    body = (strip + "".join(parts[k] for k, _l in tabs if k in parts) + others
            + _settings(p, subject, plans_of(ctx)))
    domain = (f'<a class="act act--quiet" href="https://{_e(p["domain"])}/" rel="noreferrer">'
              f'open {_e(p["domain"])}</a>' if p and p.get("domain") else "")
    actions = domain + f'<a class="act" href="/projects/{_e(subject)}/edit">Edit the contract</a>'
    return _main("project", v, [("Projects", "/"), (subject, None)], body, actions,
                 subject=subject)


# ── the concept pages ────────────────────────────────────────────────
def deployments(readings):
    v = verdict_of(readings)
    names = org_names(readings)
    parts = []
    b = reading_for(readings, "builds show")
    if b is not None:
        parts.append(_builds_section(b, names))
    else:
        parts.append('<p class="empty">no deployments were read on this page</p>')
    parts.append(_round_subset(reading_for(readings, "check"), "deployments"))
    return _main("deployments", v, [("Deployments", "/deployments")], "".join(parts))


def _hostnames_section(edge, projects):
    """Every hostname the contracts declare, with what the edge said
    about it. The verdict per hostname comes from `edge check`: a
    hostname it lists as missing is wrong; one it does not list is at
    the edge. With no edge reading at all, the rows carry no state —
    «not consulted» is not a measurement, and drawing it as one would
    be inventing a state nobody emitted."""
    if edge is not None and blind(edge):
        return _blind_section(edge, "Hostnames", "hosts", icon="globe")
    steps = steps_of(edge) if edge is not None else []
    missing = {st.get("step", "").split(":", 1)[1] for st in steps
               if st.get("step", "").startswith("hostname:")}
    mstate = {st.get("step", "").split(":", 1)[1]: state_of(st) for st in steps
              if st.get("step", "").startswith("hostname:")}
    edge_step = next((st for st in steps if st.get("step") == "edge"), None)
    exists_state = state_of(edge_step) if edge_step else None
    rows = []
    for p in projects:
        if not p.get("domain"):
            continue
        host = p["domain"]
        paths = [sv for sv in p["services"] if sv.get("public")]
        served = "".join(f'<span class="pill mono">{_e(sv["public"])} → {_e(sv["name"])}</span>'
                         for sv in sorted(paths, key=lambda s: s["public"]))
        if edge is None:
            verdict = '<span class="faint">the edge was not consulted</span>'
        elif host in missing:
            verdict = _chip(mstate[host], "missing at the edge")
        elif exists_state is not None:
            verdict = _chip(exists_state, "at the edge")
        else:
            verdict = '<span class="faint">?</span>'
        rows.append(f'<tr><td><a class="mono" href="https://{_e(host)}/" rel="noreferrer">'
                    f'{_e(host)}</a></td><td><a href="/projects/{_e(p["name"])}">{_e(p["name"])}</a>'
                    f'</td><td><div class="pills">{served}</div></td><td>{verdict}</td></tr>')
    surplus = next((st for st in steps if st.get("step") == "surplus-cnames"), None)
    tail = ""
    if surplus:
        hosts = surplus.get("hostnames") or []
        tail = (f'<h3 class="sub">At the edge, and in no contract</h3><ul class="tail">'
                + "".join(f'<li>{_chip(state_of(surplus), "surplus")}<span class="mono">{_e(h)}</span>'
                          f'<span class="note">no contract asks for this hostname; it does not '
                          f'change the verdict</span></li>' for h in hosts) + '</ul>')
    table = (f'<table class="rows hosts"><thead><tr><th>hostname</th><th>project</th>'
             f'<th>paths</th><th></th></tr></thead><tbody>{"".join(rows)}</tbody></table>'
             if rows else '<p class="empty">no contract declares a public hostname</p>')
    if edge is None:
        return (f'<section class="block" id="hosts"><header class="src-head">{_icon("globe")}'
                f'<h2>Hostnames</h2></header>{table}</section>')
    states = states_in(edge)
    if not steps:
        states.add(UNSEEN)
    n = edge_step.get("hostnames") if edge_step else None
    lead = (f"The edge holds {n} hostnames of this instance's. The ones below are the ones "
            f"your contracts declare." if n is not None else
            "The hostnames your contracts declare, as the edge answered about them.")
    return _section(edge, "Hostnames", table + tail, states, "hosts", lead=lead, icon="globe")


def domains(readings):
    v = verdict_of(readings)
    projects = projects_of(readings)
    parts = [_hostnames_section(reading_for(readings, "edge check"), projects),
             _round_subset(reading_for(readings, "check"), "domains")]
    return _main("domains", v, [("Domains", "/domains")], "".join(parts))


def traffic(readings):
    v = verdict_of(readings)
    t = reading_for(readings, "traffic show")
    body = (_traffic_section(t, org_names(readings)) if t is not None
            else '<p class="empty">no traffic was read on this page</p>')
    return _main("traffic", v, [("Traffic", "/traffic")], body)


def _declared_storage(projects):
    rows = []
    for p in projects:
        for sv in p["services"]:
            if sv["kind"] in ("postgres", "redis", "mongodb"):
                users = [o["name"] for o in p["services"] if sv["kind"] in (o.get("uses") or [])]
                rows.append(f'<tr><td><a href="/projects/{_e(p["name"])}">{_e(p["name"])}</a></td>'
                            f'<td>{_service_pill(sv)}</td><td>{_e(KIND.get(sv["kind"], sv["kind"]))}</td>'
                            f'<td>{_e(", ".join(users) or "nobody")}</td></tr>')
        if p["bucket"]:
            users = [o["name"] for o in p["services"] if "bucket" in (o.get("uses") or [])]
            rows.append(f'<tr><td><a href="/projects/{_e(p["name"])}">{_e(p["name"])}</a></td>'
                        f'<td><span class="pill">{_icon("bucket")}bucket</span></td><td>object storage</td>'
                        f'<td>{_e(", ".join(users) or "nobody")}</td></tr>')
    if not rows:
        return '<p class="empty">no contract declares a database, a cache or a bucket</p>'
    return (f'<table class="rows"><thead><tr><th>project</th><th>service</th><th>kind</th>'
            f'<th>used by</th></tr></thead><tbody>{"".join(rows)}</tbody></table>')


def storage(readings):
    v = verdict_of(readings)
    projects = projects_of(readings)
    parts = []
    b = reading_for(readings, "data remote status")
    if b is not None:
        parts.append(_backup_section(b, org_names(readings)))
    org = reading_for(readings, "org list")
    if org is not None and not blind(org):
        parts.append(_section(org, "Declared by the contracts", _declared_storage(projects),
                              states_in(org), "declared", icon="database",
                              lead="Databases, caches and buckets are provided by the platform: "
                                   "image, disk, credential and policies come out of its own "
                                   "catalogue, never out of a tenant's repository."))
    elif org is not None:
        parts.append(_blind_section(org, "Declared by the contracts", "declared", icon="database"))
    parts.append(_round_subset(reading_for(readings, "check"), "storage"))
    return _main("storage", v, [("Storage", "/storage")], "".join(parts))


def _reach_table(projects):
    rows = []
    for p in projects:
        for sv in p["services"]:
            if sv["kind"] in ("postgres", "redis", "mongodb"):
                continue
            reach = ", ".join(USES.get(u, u) for u in sv["uses"]) or "nothing at all"
            rows.append(f'<tr><td><a href="/projects/{_e(p["name"])}">{_e(p["name"])}</a></td>'
                        f'<td>{_service_pill(sv)}</td><td>{_e(reach)}</td>'
                        f'<td class="mono">{_e(sv["public"] or "")}</td></tr>')
    if not rows:
        return '<p class="empty">no contract declares a service</p>'
    return (f'<table class="rows"><thead><tr><th>project</th><th>service</th><th>may reach</th>'
            f'<th>reachable at</th></tr></thead><tbody>{"".join(rows)}</tbody></table>')


def _signing_summary(reading):
    if reading is None:
        return ""
    if blind(reading):
        return _blind_section(reading, "Signed and scanned", "signing", icon="shield")
    pushes = [st for st in steps_of(reading) if st.get("step", "").startswith("build:")]
    counts = {}
    for st in pushes:
        for k, vv in (st.get("links") or {}).items():
            counts.setdefault(k, {}).setdefault(SCREEN.get(vv, UNSEEN), 0)
            counts[k][SCREEN.get(vv, UNSEEN)] += 1
    states = states_in(reading)
    if not pushes:
        states.add(UNSEEN)
        body = f'<p class="empty" data-state="{UNSEEN}">no build was read</p>'
    else:
        cells = []
        for k in ("build", "scan", "sign", "digest"):
            c = counts.get(k) or {}
            bits = " · ".join(f'<span class="link" data-state="{s}">{n} {STATE_WORD[s] if s != FINE else "ok"}</span>'
                              for s, n in c.items())
            cells.append(f'<div class="fact"><span class="figure">{bits or "—"}</span>'
                         f'<span class="label">{_e(LINK_WORD[k])}</span></div>')
        body = (f'<div class="facts-row">{"".join(cells)}</div>'
                f'<p class="note">Of the last {len(pushes)} pushes read. A hatched count is '
                f'pushes where that link was not measured, most often because nothing was '
                f'built (only manifests changed). <a href="/deployments">Every push, link by '
                f'link, on Deployments.</a></p>')
    return _section(reading, "Signed and scanned", body, states, "signing", icon="shield")


def security(readings):
    v = verdict_of(readings)
    projects = projects_of(readings)
    parts = [_round_subset(reading_for(readings, "check"), "security"),
             _signing_summary(reading_for(readings, "builds show"))]
    org = reading_for(readings, "org list")
    if org is not None and not blind(org):
        parts.append(_section(org, "What each service may reach", _reach_table(projects),
                              states_in(org), "reach", icon="shield",
                              lead="By default a service reaches nothing: not the internet, not "
                                   "the database beside it. Each one names what it may talk to "
                                   "in the contract, and the platform enforces exactly that list."))
    parts.append(
        '<section class="block" id="console"><header class="src-head">' + _icon("shield") +
        '<h2>This console</h2></header><ul class="tail plain">'
        '<li><b>It listens on 127.0.0.1 and nowhere else</b>, and there is no flag to change '
        'that. From another machine, an SSH tunnel is the way in.</li>'
        '<li><b>It has no login of its own.</b> A page from the internet cannot borrow your '
        'browser to read it or to write through it: the host, the origin and a per-process '
        'token are checked on every request.</li>'
        '<li><b>It serves no script and fetches nothing</b>: fonts and styles travel inside '
        'the page.</li>'
        '<li><b>It writes files in this instance and nothing else</b>: no commit, no push, no '
        'cluster. What runs is what you commit.</li></ul></section>')
    return _main("security", v, [("Security", "/security")], "".join(parts))


def _capacity_section(reading):
    if blind(reading):
        return _blind_section(reading, "Capacity", "capacity", icon="chip")
    states = states_in(reading)
    figures, fits = [], []
    for st in steps_of(reading):
        name = st.get("step", "")
        state = state_of(st)
        if name.startswith("fits:"):
            plan = name.split(":", 1)[1]
            room = st.get("room")
            answer = ("could not be measured" if room is None else
                      f"{room} more" if room else "none")
            wants = []
            if st.get("wants_cpu"):
                wants.append(f'{st["wants_cpu"] / 1000:g} CPU')
            if st.get("wants_memory"):
                wants.append(_bytes(st["wants_memory"]))
            fits.append(f'<tr><td><a class="mono" href="/plans">{_e(plan)}</a></td><td class="faint">{_e(" · ".join(wants))}</td>'
                        f'<td class="mono num">{_e(answer)}</td>'
                        f'<td class="note">{_e(st["binding"]) + " runs out first" if st.get("binding") else ""}</td>'
                        f'<td>{_pip(state)}</td></tr>')
        elif name in ("capacity:memory", "capacity:cpu"):
            what = name.split(":", 1)[1]
            free = st.get("free")
            words = (_bytes(free) if what == "memory" else _cpu_words(free)) if free is not None \
                else st.get("free_human", "?")
            figures.append(_fact(f"{what} free", words))
            if st.get("allocatable"):
                figures.append(_fact(f"{what} spoken for",
                                     f'{(st.get("asked", 0) / st["allocatable"]) * 100:.0f}%'))
        elif name == "capacity:nodes":
            figures.append(_fact("nodes", _num(st.get("nodes", 0))))
            figures.append(_fact("pods asking", _num(st.get("pods", 0))))
        else:
            figures.append(_fact(name.split(":", 1)[-1], st.get("why", "not measured")))
    body = (f'<div class="facts-row head">{"".join(figures)}</div>' if figures else "")
    if fits:
        body += (f'<h3 class="sub">Room for another project</h3><table class="rows"><thead><tr>'
                 f'<th>plan</th><th>asks for</th><th class="num">would still fit</th><th></th><th></th>'
                 f'</tr></thead><tbody>{"".join(fits)}</tbody></table>'
                 f'<p class="note">«Spoken for» is what the running pods asked for, not what '
                 f'they use: a plan reserves its ceiling the moment its project exists.</p>')
    if not figures and not fits:
        states.add(UNSEEN)
        body = f'<p class="empty" data-state="{UNSEEN}">nothing was measured</p>'
    return _section(reading, "Capacity", body, states, "capacity", icon="chip")


def machine(readings):
    v = verdict_of(readings)
    c = reading_for(readings, "capacity show")
    parts = [_capacity_section(c) if c is not None else
             '<p class="empty">the capacity was not read on this page</p>',
             _round_subset(reading_for(readings, "check"), "machine")]
    return _main("machine", v, [("Machine", "/machine")], "".join(parts))


def _round_full(reading):
    if blind(reading):
        return _blind_section(reading, "The round", "round", icon="pulse")
    doc = reading.get("documento") or {}
    steps = steps_of(reading)
    states = states_in(reading)
    facts = [_fact("sections", _num(len(steps)))]
    for key, label in (("failures", "failing"), ("notices", "asking a decision")):
        if key in doc:
            facts.append(_fact(label, _num(doc[key])))
    unseen = sum(1 for st in steps if state_of(st) == UNSEEN)
    if unseen:
        facts.append(_fact("could not look", _num(unseen)))
    body = f'<div class="facts-row head">{"".join(facts)}</div>' + _round_list(steps)
    if not steps:
        states.add(UNSEEN)
    return _section(reading, "The round", body, states, "round", icon="pulse",
                    lead="Fourteen-odd sections, each with its measures. What is not fine is "
                         "open; what is fine is a line with a count.")


def health(readings):
    v = verdict_of(readings)
    parts = []
    c = reading_for(readings, "check")
    parts.append(_round_full(c) if c is not None else
                 '<p class="empty">the round was not read on this page</p>')
    e = reading_for(readings, "edge check")
    if e is not None:
        parts.append(_dump(e, "The edge", "edge", icon="globe"))
    return _main("health", v, [("Health", "/health")], "".join(parts))


def _plans_section(reading, capacity, projects):
    if blind(reading):
        return _blind_section(reading, "The plans", "plans", icon="steps")
    states = states_in(reading)
    room = {st.get("step", "").split(":", 1)[1]: st
            for st in steps_of(capacity) if st.get("step", "").startswith("fits:")}
    rows = []
    for st in steps_of(reading):
        if not st.get("step", "").startswith("plan:"):
            continue
        name = st["step"].split(":", 1)[1]
        n = st.get("numeros") or {}
        state = state_of(st)
        using = st.get("proyectos") or []
        who = ", ".join(f'<a href="/projects/{_e(o)}">{_e(o)}</a>' for o in using) or \
            '<span class="faint">nobody yet</span>'
        r = room.get(name)
        if capacity is None:
            fits = '<span class="faint">machine not read</span>'
        elif r is None:
            fits = '<span class="faint">?</span>'
        elif r.get("room") is None:
            fits = f'{_pip(state_of(r))}<span class="faint">could not be measured</span>'
        else:
            fits = (f'{_pip(state_of(r))}{r["room"]} more' if r["room"] else
                    f'{_pip(state_of(r))}none')
        shipped = st.get("de_serie")
        badge = ('<span class="badge">shipped</span>' if shipped else
                 '<span class="badge mine">yours</span>')
        action = (f'<a class="act act--quiet small" href="/plans/{_e(name)}/edit">Change</a>'
                  if not shipped else
                  f'<a class="act act--quiet small" href="/plans/new?from={_e(name)}">Start from it</a>')
        rows.append(
            f'<tr><td><b class="mono">{_e(name)}</b><br>{badge}</td>'
            f'<td class="desc">{_e(st.get("descripcion") or "")}'
            + (f'<br><span class="note">{_e(st.get("error"))}</span>' if st.get("error") else "")
            + f'</td>'
            f'<td class="num">{_e(_quantity_words("requests.cpu", n.get("requests.cpu")))}<br>'
            f'{_e(_quantity_words("requests.memory", n.get("requests.memory")))}</td>'
            f'<td class="num">{_e(_quantity_words("limits.cpu", n.get("limits.cpu")))}<br>'
            f'{_e(_quantity_words("limits.memory", n.get("limits.memory")))}</td>'
            f'<td class="num mono">{_e(n.get("pods", "?"))}</td>'
            f'<td class="num mono">{_e(n.get("persistentvolumeclaims", "?"))}</td>'
            f'<td class="num">{_e(_quantity_words("requests.storage", n.get("requests.storage")))}</td>'
            f'<td>{who}</td><td class="fits">{fits}</td><td>{action}</td></tr>')
    if not rows:
        states.add(UNSEEN)
        body = f'<p class="empty" data-state="{UNSEEN}">no plan was read</p>'
    else:
        body = (f'<table class="rows plans"><thead><tr><th>plan</th><th>what it is for</th>'
                f'<th class="num">reserves</th><th class="num">may take</th><th class="num">pods</th>'
                f'<th class="num">disks</th><th class="num">disk</th><th>used by</th>'
                f'<th>room for</th><th></th></tr></thead><tbody>{"".join(rows)}</tbody></table>'
                f'<p class="note legend"><b>Reserves</b> is what the scheduler sets aside for the '
                f'whole project and what the quota charges; <b>may take</b> is the ceiling under a '
                f'burst. CPU over the ceiling is throttled, memory over it is killed. <b>Room '
                f'for</b> is how many more projects of that plan the machine would still fit, as '
                f'Machine measured it.</p>')
    return _section(reading, "The plans", body, states, "plans", icon="steps")


def plans(readings):
    v = verdict_of(readings)
    projects = projects_of(readings)
    q = reading_for(readings, "quota list")
    parts = []
    if q is not None:
        parts.append(_plans_section(q, reading_for(readings, "capacity show"), projects))
    else:
        parts.append('<p class="empty">the plans were not read on this page</p>')
    parts.append(
        '<section class="block" id="sizes"><header class="src-head">' + _icon("steps") +
        '<h2>Two ceilings, not one</h2></header><p class="lead">The <b>plan</b> is the wall '
        'around the whole project: the apiserver refuses anything past it. Each service has a '
        '<b>size</b> of its own inside that wall (<code class="mono">tamano</code>: chico, mediano, '
        'grande), which is what one container may reserve and burst to. Their sum has to fit '
        'in the plan, and the generator says so before anything is written, naming the plan '
        'that would hold it.</p></section>')
    actions = '<a class="act" href="/plans/new">New plan</a>'
    return _main("plans", v, [("Plans", "/plans")], "".join(parts), actions)


VIEWS = {"projects": overview, "deployments": deployments, "domains": domains,
         "traffic": traffic, "storage": storage, "security": security,
         "machine": machine, "health": health, "plans": plans}


def render(readings, subject=None, view=None, instance=None):
    """A whole screen: the frame and the page. `subject` names one
    project; `view` names one of the concept pages; neither is the
    overview, which is what checks 122 and 127 render."""
    if subject:
        main = project(readings, subject, instance)
        return frame(main, list(instance or []) or list(readings), "projects", subject)
    key = view or "projects"
    main = VIEWS.get(key, overview)(readings)
    return frame(main, readings, key)
