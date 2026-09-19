"""What exists upstream, measured — never assumed, never listed.

THE ONE RULE. This module answers «what is published today» and nothing
else. It never decides that a newer thing is the right thing: that is a
judgement about release notes, migrations and taste, and a sort cannot
make it. It reports, and `aegis update plan` proposes.

THE FOUR ANSWERS, and the fourth is why this file is careful:

    al día        the pin is on the newest candidate
    atrasado      there is a newer candidate, named
    desaparecido  the pinned tag NO LONGER EXISTS upstream (wrong)
    no medible    unreachable, rate-limited, or a tag scheme nobody can
                  order. NOT «up to date»: a registry that did not
                  answer is not a registry that said yes.

WHY A TAG SCHEME CAN BE UNORDERABLE, and why that is honest rather than
lazy: `jenkins/inbound-agent:3355.v388858a_47b_33-23` carries a build
number and a git hash. Sorting those by version is inventing an order
the publisher never promised, and a window that acts on an invented
order updates to something nobody chose.

THE CACHE has an age and every value carries when it was measured, for
the same reason every screen of the console does: a right answer from
this morning, shown as if it were now, is the oldest lie a dashboard
tells.
"""
import datetime
import json
import os
import pathlib
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

# ── the six answers, and why there are six and not four ──────────────
# The first four were the plan's. Writing the console's Updates page
# found that the fourth was carrying three different things under one
# name, and the difference matters more here than almost anywhere:
#
#   al-dia        the pin is on the newest candidate
#   atrasado      there is a newer one, and it is named
#   desaparecido  the pinned tag no longer exists upstream
#   sin-arriba    THERE IS NOBODY TO ASK. An image this instance builds
#                 has no upstream: its version is a tag of the chain.
#                 That is an ANSWER, complete and permanent.
#   sin-orden     upstream answered and its tags cannot be ordered
#                 (`3355.v388858a_47b_33-23`, `nonroot`). Also an
#                 answer: we know exactly why no window can bump it, and
#                 the reason will be the same tomorrow.
#   no-medible    the instrument never reached the subject: a timeout, a
#                 429, a repository that would not talk. THIS one, and
#                 only this one, is rc 2.
#
# Collapsing the middle two into «I could not look» is what the product
# exists to prevent, one level up: it made `inventory` exit 2 for ever
# on a healthy instance, and a verdict that never changes is a verdict
# nobody reads. Each of the two is a measurement with a reason attached,
# and neither will ever become measurable by trying again.
AL_DIA, ATRASADO, DESAPARECIDO = "al-dia", "atrasado", "desaparecido"
SIN_ARRIBA, SIN_ORDEN, NO_MEDIBLE = "sin-arriba", "sin-orden", "no-medible"

#: The answers that mean «this was measured», whatever they measured.
#: `inventory` reports these as `already`; only NO_MEDIBLE is rc 2.
MEASURED = (AL_DIA, SIN_ARRIBA, SIN_ORDEN)
#: The answers a window can never act on, each for its own written
#: reason. They are not failures and they do not wait for a retry.
UNACTIONABLE = (SIN_ARRIBA, SIN_ORDEN)

OCI_ACCEPT = ", ".join((
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json",
))
TIMEOUT = 20
CACHE_TTL = 6 * 3600


def _now():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


class Answer:
    """What upstream says about one pin."""

    def __init__(self, state, latest=None, why=None, digest=None, candidates=None):
        self.state = state
        self.latest = latest
        self.why = why
        self.digest = digest
        self.candidates = candidates or []
        self.measured_at = _now()

    def as_data(self):
        d = {"arriba": self.state, "medido_en": self.measured_at}
        if self.latest:
            d["ultima"] = self.latest
        if self.digest:
            d["digest_arriba"] = self.digest
        if self.why:
            d["por_que"] = self.why
        if self.candidates:
            d["candidatas"] = self.candidates[:5]
        return d


# ── the registry, read the way aegis-image reads it ──────────────────
def _endpoint(host):
    return "registry-1.docker.io" if host in ("docker.io", "index.docker.io") else host


def _split_repo(name):
    """`quay.io/prometheus/alertmanager` → (host, path). A name with no
    dot and no colon in its first element is Docker Hub, and a single
    element there lives under `library/`."""
    first = name.split("/", 1)[0]
    if "." in first or ":" in first or first == "localhost":
        host, path = name.split("/", 1) if "/" in name else (name, "")
    else:
        host, path = "docker.io", name
    if host in ("docker.io", "index.docker.io") and "/" not in path:
        path = f"library/{path}"
    return _endpoint(host), path


def _get(url, headers=None, token=None):
    req = urllib.request.Request(url, headers=dict(headers or {}))
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.status, r.headers, r.read()


def _retry(fn, tries=3):
    """A registry that says «too many requests» has not said no. Three
    attempts with a widening wait, the same shape `retry_net` has in
    bash: without it a rate limit reads as «nobody could measure this»,
    which is true for that second and misleading for the day."""
    import time as _t
    for n in range(tries):
        try:
            return fn()
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503, 504) or n == tries - 1:
                raise
            _t.sleep(2 ** n * 3)
        except urllib.error.URLError:
            if n == tries - 1:
                raise
            _t.sleep(2 ** n * 3)


def _fetch(url, path, accept=OCI_ACCEPT, head=False):
    """One call; if the registry answers 401 it plays the challenge it
    just handed over and calls again. Anything that is not a 200 raises
    with its code said out loud — the port of `oci_fetch`."""
    headers = {"Accept": accept}
    req = urllib.request.Request(url, headers=headers, method="HEAD" if head else "GET")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.headers, r.read()
    except urllib.error.HTTPError as e:
        if e.code != 401:
            raise
        chal = e.headers.get("WWW-Authenticate") or ""
        if not chal.lower().startswith("bearer"):
            raise RuntimeError("401 without a Bearer challenge: this registry wants "
                               "credentials aegis does not have")
        parts = dict(re.findall(r'(\w+)="([^"]*)"', chal))
        realm = parts.get("realm")
        if not realm:
            raise RuntimeError("the challenge names no realm")
        q = {"scope": parts.get("scope") or f"repository:{path}:pull"}
        if parts.get("service"):
            q["service"] = parts["service"]
        _st, _h, body = _get(f"{realm}?{urllib.parse.urlencode(q)}")
        token = (json.loads(body) or {}).get("token") or (json.loads(body) or {}).get("access_token")
        if not token:
            raise RuntimeError("the realm did not hand out an anonymous pull token")
        req = urllib.request.Request(url, headers=headers, method="HEAD" if head else "GET")
        req.add_header("Authorization", f"Bearer {token}")
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.headers, r.read()


def tag_digest(name, tag):
    """What the tag points at TODAY, or None if the tag is gone."""
    host, path = _split_repo(name)
    url = f"https://{host}/v2/{path}/manifests/{urllib.parse.quote(tag)}"
    try:
        headers, body = _retry(lambda: _fetch(url, path, head=True))
    except urllib.error.HTTPError as e:
        if e.code in (404, 403):
            return None
        raise
    d = headers.get("Docker-Content-Digest")
    if not (d or "").startswith("sha256:"):
        headers, body = _fetch(url, path)
        import hashlib
        d = "sha256:" + hashlib.sha256(body).hexdigest()
    return d


def tags(name):
    host, path = _split_repo(name)
    _h, body = _retry(lambda: _fetch(f"https://{host}/v2/{path}/tags/list", path,
                                     accept="application/json"))
    return (json.loads(body) or {}).get("tags") or []


# ── ordering, and refusing to order what cannot be ───────────────────
_NUM = re.compile(r"^v?(\d+(?:\.\d+)*)(.*)$")


def shape(tag):
    """(numbers, suffix) of a tag, or None when it has no orderable
    number at its head. `1.36`, `v0.28.0`, `3.12-slim` have one;
    `3355.v388858a_47b_33-23` and `nonroot` do not."""
    m = _NUM.match(tag or "")
    if not m:
        return None
    nums = tuple(int(x) for x in m.group(1).split("."))
    suffix = m.group(2)
    # A suffix with a hash or a build id in it is not a shape: two tags
    # that share it are not comparable, they are just both weird.
    if re.search(r"[0-9a-f]{7,}", suffix):
        return None
    return nums, suffix


def newer(current, every, same_major=True):
    """The tags that sort above `current` and carry its exact shape.

    SHAPE INCLUDES HOW MANY NUMBERS THE TAG HAS, and that is not
    pedantry: `alpine:3.22` follows a SERIES and `alpine:3.24.2` is a
    point release of another one. Offering the second to somebody who
    pinned the first changes what the tag means — from «the 3.22 line,
    patched» to «this exact build». The first version of this function
    compared only the suffix and proposed exactly that for alpine,
    busybox and python.

    Same major by default: a major is a decision, never a default.
    """
    cur = shape(current)
    if not cur:
        return []
    out = []
    for t in every:
        s = shape(t)
        if not s or s[1] != cur[1] or len(s[0]) != len(cur[0]):
            continue
        if s[0] <= cur[0]:
            continue
        if same_major and s[0][0] != cur[0][0]:
            continue
        out.append((s[0], t))
    out.sort()
    return [t for _n, t in out]


# ── one answer per class ─────────────────────────────────────────────
def for_image(name, tag, digest=None, same_major=True):
    """An image: is the pinned tag still there, did its digest move, and
    is there a newer tag of the same shape."""
    try:
        d = tag_digest(name, tag) if tag else None
    except Exception as e:                                # noqa: BLE001
        return Answer(NO_MEDIBLE, why=f"{type(e).__name__}: {e}")
    if tag and d is None:
        return Answer(DESAPARECIDO, why=f"the tag {tag} no longer exists upstream")
    try:
        every = tags(name)
    except Exception as e:                                # noqa: BLE001
        # The digest was read and the tag list was not: that is enough
        # to say whether the pin moved, and not enough to say whether a
        # newer one exists. Both facts travel.
        moved = digest and d and d != digest
        return Answer(NO_MEDIBLE if not moved else ATRASADO, latest=tag if moved else None,
                      digest=d, why=f"tags: {type(e).__name__}: {e}")
    ahead = newer(tag, every, same_major)
    if ahead:
        return Answer(ATRASADO, latest=ahead[-1], digest=d, candidates=ahead)
    if not shape(tag):
        # SIN_ORDEN and not NO_MEDIBLE: upstream answered, its tags were
        # read, and the thing that cannot be done is ordering them.
        # Calling that «I could not look» made this line permanently rc
        # 2 on an instance whose CI agent is pinned at
        # `3355.v388858a_47b_33-23`, which is a tag scheme, not a fault.
        return Answer(SIN_ORDEN, digest=d,
                      why=f"the tag {tag!r} has no orderable shape: upstream publishes "
                          f"{len(every)} tags and nobody can say which is «newer». A "
                          f"window will never bump this one; a human chooses it")
    if digest and d and d != digest:
        return Answer(ATRASADO, latest=tag, digest=d,
                      why="the same tag now points at other content upstream")
    return Answer(AL_DIA, digest=d)


def _spelling(current, answer):
    """Say it out loud when upstream spells the version differently from
    the pin (`v1.20.2` here, `1.20.2` there). It is not a finding, it is
    a fact whoever writes the bump has to honour: a tag with the wrong
    `v` is a tag that does not exist."""
    if answer.latest and current and answer.latest.startswith("v") != current.startswith("v"):
        answer.why = ((answer.why + " · ") if answer.why else "") + \
            f"upstream spells it {answer.latest!r} and the pin is written {current!r}"
    return answer


def for_chart(repo, chart, version, same_major=True):
    """A helm chart: the newest version its repository publishes."""
    if not repo:
        return Answer(NO_MEDIBLE, why="the Application declares no repoURL")
    # A repoURL with no scheme is an OCI registry: helm accepts
    # `quay.io/jetstack/charts` and so does the Application that pins
    # cert-manager. Reading it as http answers «unknown url type» about
    # a chart that is perfectly measurable.
    if repo.startswith("oci://") or "://" not in repo:
        base = repo[len("oci://"):] if repo.startswith("oci://") else repo
        return for_image(f"{base.rstrip('/')}/{chart}", version, same_major=same_major)
    try:
        import yaml
        _h, body = _fetch(f"{repo.rstrip('/')}/index.yaml", "", accept="application/json")
        index = yaml.safe_load(body) or {}
    except Exception as e:                                # noqa: BLE001
        return Answer(NO_MEDIBLE, why=f"{type(e).__name__}: {e}")
    every = [e.get("version") for e in (index.get("entries") or {}).get(chart, [])
             if e.get("version") and not re.search(r"[-+](alpha|beta|rc|dev)", e["version"])]
    if not every:
        return Answer(NO_MEDIBLE, why=f"the index of {repo} carries no chart named {chart}")
    if version not in every:
        return Answer(DESAPARECIDO, why=f"the index no longer publishes {chart} {version}")
    ahead = newer(version, every, same_major)
    return _spelling(version, Answer(ATRASADO, latest=ahead[-1], candidates=ahead)) \
        if ahead else Answer(AL_DIA)


def for_release(repo, current, same_major=True):
    """A GitHub release line, read with `gh` — which the instance has
    authenticated as a prerequisite (the init refuses without it)."""
    try:
        out = subprocess.run(["gh", "api", f"repos/{repo}/releases?per_page=60",
                              "--jq", ".[] | select(.draft==false and .prerelease==false) | .tag_name"],
                             capture_output=True, text=True, timeout=TIMEOUT * 2)
    except Exception as e:                                # noqa: BLE001
        return Answer(NO_MEDIBLE, why=f"gh: {type(e).__name__}: {e}")
    if out.returncode != 0:
        return Answer(NO_MEDIBLE, why=f"gh api {repo}: {(out.stderr or '').strip()[:120]}")
    every = [t.strip() for t in out.stdout.splitlines() if t.strip()]
    ahead = newer(current, every, same_major)
    return Answer(ATRASADO, latest=ahead[-1], candidates=ahead) if ahead else Answer(AL_DIA)


# Where each host tool's releases live. It is a map of NAMES to
# repositories, not a map of versions: no version is written here.
RELEASES = {
    "tofu": "opentofu/opentofu", "sops": "getsops/sops", "age": "FiloSottile/age",
    "helm": "helm/helm", "cosign": "sigstore/cosign", "k3s": "k3s-io/k3s",
    "gh": "cli/cli", "kubectl": "kubernetes/kubernetes",
}


def for_tool(tool, current, same_major=True):
    repo = RELEASES.get(tool)
    if not repo:
        return Answer(NO_MEDIBLE, why=f"nobody knows where {tool} publishes its releases")
    # k3s tags carry the +k3sN suffix; the shape rule handles it.
    a = for_release(repo, current, same_major)
    # THE ANSWER IS SPELLED THE WAY THE PIN IS. Upstream tags releases
    # `v1.3.2` and `userland_pins` writes `1.2.1`; handing the `v` back
    # would make a bump write a version the installer's URL does not
    # build. The number is the same; the spelling is the file's.
    if a.latest and not (current or "").startswith("v"):
        a.latest = a.latest.lstrip("v")
        a.candidates = [c.lstrip("v") for c in a.candidates]
    return a


#: The name of the registry this instance runs. An image whose name
#: starts with it is an OUTPUT of the supply chain, not a choice with an
#: upstream: its tag moves when the chain is rebuilt.
OWN_REGISTRY = "registry.registry-system.svc.cluster.local"


def for_pin(pin, same_major=True):
    """What upstream says about one pin — or that there is nobody to ask.

    THE FIRST QUESTION IS WHETHER THERE IS A QUESTION. Three of the pins
    on the author's instance are images aegis builds itself, and one
    class (`apt`) is measured against the machine rather than against a
    registry. Neither is «I could not look»: they are complete answers,
    and reporting them as failures to measure made `inventory` exit 2
    every day on an instance where nothing was wrong. Check 216 drives
    this function for exactly that.
    """
    if pin.cls in ("mirror", "containerfile", "raw-image", "jenkinsfile"):
        if pin.extra.get("interno") or pin.name.startswith(OWN_REGISTRY):
            return Answer(SIN_ARRIBA,
                          why="it is built by this instance: its version is a tag of the "
                              "chain, not a choice with an upstream. It moves when the "
                              "chain is rebuilt, never by a bump")
        return for_image(pin.name, pin.current, pin.digest, same_major=same_major)
    if pin.cls == "chart":
        return for_chart(pin.extra.get("repo"), pin.extra.get("chart"), pin.current,
                         same_major=same_major)
    if pin.cls in ("k3s", "userland"):
        return for_tool(pin.name, pin.current, same_major=same_major)
    return Answer(SIN_ARRIBA, why="measured against the machine, not upstream")


def apt_upgradable():
    """What the machine says it could upgrade, and which of those touch
    the kernel or the graphics driver — the two that cannot be undone
    and are never part of the automatic layer."""
    try:
        out = subprocess.run(["apt-get", "-s", "upgrade"], capture_output=True, text=True,
                             timeout=120, env={**os.environ, "LC_ALL": "C"})
    except Exception as e:                                # noqa: BLE001
        return None, f"{type(e).__name__}: {e}"
    if out.returncode != 0:
        return None, (out.stderr or "").strip()[:160]
    pkgs = [ln.split()[1] for ln in out.stdout.splitlines() if ln.startswith("Inst ")]
    kernel = re.compile(r"^(linux-(image|headers|modules|objects)|.*nvidia.*)")
    return {"todos": sorted(pkgs),
            "nucleo": sorted(p for p in pkgs if kernel.match(p)),
            "resto": sorted(p for p in pkgs if not kernel.match(p))}, None


# ── the cache ────────────────────────────────────────────────────────
def cache_path():
    from . import paths
    return pathlib.Path(paths.aegis_home()) / ".cache" / "aegis-update" / "upstream.json"


#: The vocabulary the cached answers are written in. A cache holds the
#: WORD upstream's answer was given, so when the words change an old
#: entry is not stale, it is in another language — and it would be read
#: back for six hours as if it still meant what it said. Bump this
#: whenever a state is added, removed or renamed. Measured the day
#: `no-medible` became three answers: every entry of the old cache came
#: back saying «I could not look» about pins that had just been
#: reclassified.
CACHE_VOCABULARY = 2


def load_cache(fresh=False):
    if fresh:
        return {}
    p = cache_path()
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if data.get("vocabulario") != CACHE_VOCABULARY:
        return {}
    import time
    cut = time.time() - CACHE_TTL
    return {k: v for k, v in (data.get("entries") or {}).items()
            if (v.get("epoch") or 0) > cut}


def save_cache(entries):
    import time
    p = cache_path()
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        stamped = {k: {**v, "epoch": v.get("epoch") or time.time()} for k, v in entries.items()}
        p.write_text(json.dumps({"vocabulario": CACHE_VOCABULARY, "entries": stamped},
                                ensure_ascii=False), encoding="utf-8")
    except OSError:
        # A cache that cannot be written is a slower command, never a
        # wrong one.
        pass
