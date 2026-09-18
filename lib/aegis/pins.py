"""What this tree pins, derived and never listed.

WHY THIS EXISTS. aegis pins a version or a digest for everything it
runs, and the doctrine forbids a summary of them: every pin lives ONLY
where it is consumed (seed/platform/ansible/inventory/group_vars/all.yml
opens with the rule, and check 012b goes red the day a pin index comes
back). A summary would be a mirror with no consumer, which is drift with
a nicer name.

So this module does not hold a list: it READS THE TREE, every time, the
same six places the doctrine names. Adding a chart, a mirrored image or
a Jenkinsfile makes it appear here with no edit. A class that comes back
empty is a class whose derivation broke, and check 206 says so out loud
rather than reporting «nothing to update».

WHAT A PIN IS. One thing whose version somebody chose, with everywhere
that choice is written down. The same image named in six Jenkinsfiles is
ONE pin with six locations, because bumping it means editing six lines
in one commit — and a bump that edits five of them is the bug this
shape exists to make visible.
"""
import os
import pathlib
import re

# The classes, in the order a window would move them: the ground first,
# what stands on it after. `layer` is the number the update protocol
# uses; `writes` says whether a bump is a file edit here or a command
# somewhere else.
CLASSES = {
    "apt":           {"layer": 1, "writes": "host"},
    "userland":      {"layer": 2, "writes": "group_vars"},
    "k3s":           {"layer": 3, "writes": "group_vars"},
    "chart":         {"layer": 4, "writes": "file"},
    "raw-image":     {"layer": 5, "writes": "file"},
    "mirror":        {"layer": 6, "writes": "command"},
    "containerfile": {"layer": 7, "writes": "file"},
    "jenkinsfile":   {"layer": 8, "writes": "file"},
}

# What is NOT a pin of this tree, wherever it appears: the platform's own
# registry (those digests are outputs of the chain, not choices), and the
# placeholders the seed carries by design (check 003 sweeps them).
INTERNAL = re.compile(r"registry\.registry-system\.svc\.cluster\.local:5000/")
PLACEHOLDER = re.compile(r"__[A-Z0-9_]+__|VERIFICAR|CHANGEME")

# `[^\S\n]*` and not `\s*`: a bare `image:` opening a YAML block
# (jenkins' values does exactly that) let the pattern walk to the
# next line and capture the key under it as if it were a reference.
_IMAGE_LINE = re.compile(r"^[^\S\n]*(?:-[^\S\n]+)?image:[^\S\n]*['\"]?([^'\"\s#]+)['\"]?", re.M)
# `[^\S\n]*` and not `\s*`, for the second time: `\s` matches a newline,
# so `^\s*FROM` starting at a BLANK line walks into the next one and the
# match —and therefore the line number— belongs to the blank line above.
# The first time was the image: of a yaml block (stage A); this one was
# found on 2026-09-18 by the check that demands the recorded line
# actually carry the version, on the one Containerfile with a blank line
# between two FROMs.
_FROM_LINE = re.compile(r"^[^\S\n]*FROM[^\S\n]+(\S+)", re.M | re.I)


class Pin:
    """One choice of version, and every place it is written."""

    def __init__(self, cls, name, current, where, digest=None, extra=None):
        self.cls = cls
        self.name = name
        self.current = current
        self.digest = digest
        self.where = list(where)          # [(path, line), …]
        self.extra = extra or {}

    @property
    def key(self):
        return f"{self.cls}:{self.name}"

    @property
    def layer(self):
        return CLASSES[self.cls]["layer"]

    def as_step(self):
        """The shape this pin takes inside a document."""
        d = {"clase": self.cls, "nombre": self.name, "version": self.current,
             "donde": [{"fichero": p, "linea": n} for p, n in self.where],
             "capa": self.layer}
        if self.digest:
            d["digest"] = self.digest
        d.update(self.extra)
        return d

    def __repr__(self):                                   # pragma: no cover
        return f"<Pin {self.key} {self.current}>"


def _rel(root, path):
    try:
        return str(pathlib.Path(path).relative_to(root))
    except ValueError:
        return str(path)


def _lineno(text, index):
    return text.count("\n", 0, index) + 1


def _split_ref(ref):
    """`name:tag@sha256:…` → (name, tag, digest), by the registries' own
    rule and not by a regex that guesses.

    A COLON IS NOT ALWAYS A TAG. `registry:3.1.1` is a name and a tag;
    `registry.registry-system…:5000/garage` is a host with a PORT and no
    tag at all. The rule is positional: the colon opens a tag only when
    it comes after the last slash. The first version of this function
    tried to spell that as one regular expression, and quietly returned
    «no tag» for half the tree — five raw images and two CI images
    vanished from the inventory, which is exactly the silence this
    module exists to prevent.
    """
    digest = None
    if "@" in ref:
        ref, digest = ref.split("@", 1)
    tag = None
    slash = ref.rfind("/")
    colon = ref.rfind(":")
    if colon > slash:
        ref, tag = ref[:colon], ref[colon + 1:]
    return ref, tag, digest


def _merge(pins, cls, name, current, where, digest=None, extra=None):
    """One pin per (class, name); a second sighting adds a location.

    A DISAGREEMENT IS RECORDED, NOT RESOLVED: if the same image is
    pinned at two versions in two files, `conflicto` carries both and
    the check that reads it goes red. Picking one here would hide
    exactly the drift this module exists to surface.
    """
    key = (cls, name)
    if key in pins:
        p = pins[key]
        p.where.extend(where)
        if current != p.current:
            p.extra.setdefault("conflicto", []).append(current)
        return p
    p = Pin(cls, name, current, where, digest, extra)
    pins[key] = p
    return p


# ── the six readers ──────────────────────────────────────────────────
def _mirror(root, platform, pins):
    """seed/platform/mirror-images/images.txt — third parties mirrored
    into the internal registry. Two fields, tag AND digest in the
    source, exactly as check 135 demands."""
    f = platform / "mirror-images" / "images.txt"
    if not f.is_file():
        return
    text = f.read_text(encoding="utf-8")
    for i, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        source = line.split()[0]
        name, tag, digest = _split_ref(source)
        _merge(pins, "mirror", name, tag, [(_rel(root, f), i)], digest,
               {"destino": line.split()[-1] if len(line.split()) > 1 else None})


def _containerfiles(root, platform, pins):
    """The FROMs of the images aegis owns and of its CI images. Only the
    public ones: a FROM of the internal registry is an output of the
    chain and its digest is bumped by rebuilding, never by hand."""
    for d in ("base-images", "ci-images"):
        base = platform / d
        if not base.is_dir():
            continue
        for f in sorted(base.rglob("Containerfile")):
            text = f.read_text(encoding="utf-8")
            for m in _FROM_LINE.finditer(text):
                ref = m.group(1)
                if INTERNAL.search(ref) or PLACEHOLDER.search(ref) or "$" in ref:
                    continue
                name, tag, digest = _split_ref(ref)
                _merge(pins, "containerfile", name, tag,
                       [(_rel(root, f), _lineno(text, m.start()))], digest)


def _charts(root, platform, pins):
    """Every helm chart an Application declares, with the version it is
    pinned at. Read as text and not with a yaml parser on purpose: the
    line number is half the answer for a command that has to edit it."""
    apps = platform / "k8s" / "argocd-apps"
    if not apps.is_dir():
        return
    for f in sorted(apps.glob("*.yaml")):
        text = f.read_text(encoding="utf-8")
        app = None
        chart = repo = None
        chart_line = 0
        for i, line in enumerate(text.splitlines(), 1):
            m = re.match(r"^\s*name:\s*(\S+)", line)
            if m and app is None:
                app = m.group(1)
            if re.match(r"^\s*-?\s*repoURL:\s*(\S+)", line):
                repo = re.match(r"^\s*-?\s*repoURL:\s*(\S+)", line).group(1)
            m = re.match(r"^\s*chart:\s*(\S+)", line)
            if m:
                chart, chart_line = m.group(1), i
            m = re.match(r"^\s*targetRevision:\s*(\S+)", line)
            if m and chart:
                # KEYED BY THE APPLICATION and not by the chart: two
                # Applications can ride the same chart at different
                # versions (vlogs and vlogs-events do), and the thing a
                # window bumps and syncs is an Application.
                _merge(pins, "chart", app or chart, m.group(1), [(_rel(root, f), i)],
                       None, {"repo": repo, "chart": chart, "linea_chart": chart_line})
                chart = None
            if re.match(r"^---\s*$", line):
                app, chart, repo = None, None, None


def _raw_images(root, platform, pins):
    """`image:` written by hand in the manifests and in the chart values:
    the pins no chart and no mirror list carries, and which nothing
    watches today."""
    base = platform / "k8s"
    if not base.is_dir():
        return
    for f in sorted(base.rglob("*.yaml")):
        if "argocd-apps" in f.parts:
            continue
        text = f.read_text(encoding="utf-8")
        for m in _IMAGE_LINE.finditer(text):
            ref = m.group(1)
            if INTERNAL.search(ref) or PLACEHOLDER.search(ref) or "$" in ref or ref in ("", '""'):
                continue
            name, tag, digest = _split_ref(ref)
            if not tag and not digest:
                continue
            _merge(pins, "raw-image", name, tag,
                   [(_rel(root, f), _lineno(text, m.start()))], digest)


def _jenkinsfiles(root, platform, pins):
    """The pod templates of the CI. The same image is named in six
    files; one pin, six locations, so that a bump that forgets one is
    visible instead of silent."""
    for f in sorted(platform.rglob("Jenkinsfile*")):
        text = f.read_text(encoding="utf-8")
        for m in _IMAGE_LINE.finditer(text):
            ref = m.group(1).strip("'\"")
            if PLACEHOLDER.search(ref) or "$" in ref:
                continue
            internal = bool(INTERNAL.search(ref))
            name, tag, digest = _split_ref(ref)
            if not tag:
                continue
            # An internal CI image IS a choice here (its tag is written
            # by hand in every Jenkinsfile), so it is kept — with a mark,
            # because upstream for it is this instance's own registry.
            _merge(pins, "jenkinsfile", name, tag,
                   [(_rel(root, f), _lineno(text, m.start()))], digest,
                   {"interno": internal} if internal else None)


def _group_vars(root, platform, pins):
    """k3s and the host's userland. The file is the instance's copy —
    phase 05 reads that one — so an instance that drifted from the seed
    shows its own numbers here."""
    f = platform / "ansible" / "inventory" / "group_vars" / "all.yml"
    if not f.is_file():
        return
    text = f.read_text(encoding="utf-8")
    for i, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^\s*k3s_version:\s*[\"']?([^\"'\s#]+)", line)
        if m:
            _merge(pins, "k3s", "k3s", m.group(1), [(_rel(root, f), i)])
    m = re.search(r"^userland_pins:\s*$", text, re.M)
    if not m:
        return
    start = m.end()
    # `_lineno(text, start)` and NOT one more. The match of
    # `^userland_pins:\s*$` ends BEFORE its newline, so the first
    # element `.splitlines()` hands back is the empty tail of that same
    # line: numbering it as the next one puts every pin below it one
    # line too far down. Measured 2026-09-18 by check 207, which writes
    # into the line the inventory points at — tofu was reported at the
    # line of the comment beside it, and an edit would have gone into
    # the comment. The inventory had been «right» for as long as nobody
    # wrote anything.
    for i, line in enumerate(text[start:].splitlines(), _lineno(text, start)):
        if line.strip() and not line.startswith((" ", "\t", "#")):
            break
        mm = re.match(r"^\s+([a-z0-9_]+):\s*[\"']?([^\"'\s#]+)", line)
        if not mm:
            continue
        tool, version = mm.group(1), mm.group(2)
        # `apt` is not a version: it says «whatever the distribution
        # ships», and what it pins is presence. Those belong to the apt
        # class, which is measured against the machine and not upstream.
        cls = "apt" if version == "apt" else "userland"
        _merge(pins, cls, tool, None if version == "apt" else version,
               [(_rel(root, f), i)])


READERS = (_mirror, _containerfiles, _charts, _raw_images, _jenkinsfiles, _group_vars)


def read(tree=None):
    """Every pin of a tree, by key. `tree` is a platform directory (the
    instance's) or a product root; both shapes are accepted so that the
    checks can run the same instrument over the seed."""
    root = pathlib.Path(tree) if tree else None
    if root is None:
        from . import paths
        root = paths.platform_dir()
    root = root.resolve()
    platform = root / "seed" / "platform" if (root / "seed" / "platform").is_dir() else root
    pins = {}
    for reader in READERS:
        reader(root, platform, pins)
    return pins


def by_class(pins):
    out = {}
    for p in pins.values():
        out.setdefault(p.cls, []).append(p)
    for v in out.values():
        v.sort(key=lambda p: p.name)
    return out
