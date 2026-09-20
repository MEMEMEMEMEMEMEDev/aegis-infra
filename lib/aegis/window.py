"""The update window's machinery: the photo, what «a new failure» means,
the journal, the edits, and the way back.

WHY THIS IS A MODULE AND NOT A SCRIPT. Everything here is exercised by
the checks without a cluster, without a network and without touching
the instance: 207 drives the edits and the way back over a tree in
tmpfs, 208 drives the refusals against a window that must not run its
first hook, 212 reads the journal a run leaves behind. A window whose
mechanics can only be tested by opening one on the live machine would
be tested once, in anger, at the worst possible moment.

THE ONE IDEA. A window is allowed to change things because it can prove
two things afterwards: that nothing that worked stopped working, and
that everything it did can be undone. Both of those are measurements,
and a measurement that cannot be taken is never a pass. Hence the shape
of every function below: it says what it saw, or it says it could not
look, and it never rounds the second one down to the first.
"""
import datetime
import json
import pathlib
import re
import subprocess
import time

from . import cli, paths

# ── the record on disk ───────────────────────────────────────────────
# Everything a window writes lives under one directory named after the
# window. `last` names the current one. This is what `aegis update
# status` reads and what check 212 demands be complete.
STATE = "updates"
BEFORE, AFTER, REPORT, DIARY = "before.json", "after.json", "report.json", "journal.jsonl"

OUTCOMES = ("accepted", "rolled-back", "needs-a-human", "refused", "rehearsed")


def updates_dir(home=None):
    base = pathlib.Path(home) if home else paths.aegis_home()
    return base / ".init-state" / STATE


def new_id(now=None):
    """A window's name is the minute it opened, in UTC. Sortable, unique
    enough for something that happens monthly, and it says when without
    anybody having to open the file."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return now.strftime("%Y%m%dT%H%M%SZ")


# ══════════════════════════════════════════════════════════════════════
#  git, and nothing more of it than the window needs
# ══════════════════════════════════════════════════════════════════════
class GitTrouble(Exception):
    """git could not be asked, or answered something nobody should act on."""


def git(root, *args, check=True):
    r = subprocess.run(["git", "-C", str(root), *args],
                       capture_output=True, text=True, timeout=120)
    if check and r.returncode != 0:
        raise GitTrouble(f"git {' '.join(args)}: {(r.stderr or r.stdout).strip()[:300]}")
    return r.returncode, (r.stdout or "").rstrip("\n"), (r.stderr or "").rstrip("\n")


def head(root):
    return git(root, "rev-parse", "HEAD")[1]


def is_repo(root):
    return (pathlib.Path(root) / ".git").exists()


def dirty(root):
    """What is not committed, as a list of lines. Empty means clean, and
    the difference between «clean» and «I could not ask» is an
    exception, never an empty list."""
    return [ln for ln in git(root, "status", "--porcelain")[1].splitlines() if ln.strip()]


def unpushed(root):
    """Commits that exist here and not in the remote the branch tracks.

    A window that starts on an unpushed commit leaves the instance in a
    state ArgoCD never sees: the cluster keeps converging on the remote
    while the tree on disk says something else, and the acceptance
    measures a platform nobody deployed. With no upstream configured at
    all the question cannot be answered, and that is what it says."""
    rc, _, _ = git(root, "rev-parse", "--abbrev-ref", "@{upstream}", check=False)
    if rc != 0:
        raise GitTrouble("this branch tracks no remote: nobody can say whether "
                         "what is here has been published, and a window converges "
                         "through the remote")
    return [ln for ln in git(root, "log", "--oneline", "@{upstream}..HEAD")[1].splitlines()
            if ln.strip()]


def commit(root, files, subject):
    """One commit, with exactly the files named. Returns its sha.

    `git commit` with a path list and nothing else: never `-a`, never
    `add .`. A window that stages what it did not write would carry the
    operator's unrelated work into a commit its own rollback then
    reverts, and that is the one class of damage a rollback must not be
    able to do."""
    rel = [str(f) for f in files]
    git(root, "add", "--", *rel)
    rc, out, err = git(root, "commit", "-m", subject, "--", *rel, check=False)
    if rc != 0:
        raise GitTrouble(f"the commit «{subject}» did not happen: {(err or out).strip()[:300]}")
    return head(root)


def revert(root, sha):
    """Undo one commit, keeping its own commit in the history.

    `revert` and not `reset`: the history of a window is evidence, and
    an instance whose way back is «pretend it never happened» cannot
    answer what it did last month. It also keeps the remote a
    fast-forward, so the rollback is a push like any other and never a
    force."""
    rc, out, err = git(root, "revert", "--no-edit", sha, check=False)
    if rc != 0:
        # Leave nothing half applied: a conflicted revert that stays in
        # the index is a repo the next step cannot even read.
        git(root, "revert", "--abort", check=False)
        raise GitTrouble(f"the commit {sha[:12]} does not revert cleanly "
                         f"({(err or out).strip()[:200]}) — the tree was left as it was")
    return head(root)


def tree_hash(root):
    """What the tree IS, as one hash git computes. This is what «byte for
    byte the same» means when a rollback claims it: not the same diff,
    the same content."""
    return git(root, "rev-parse", "HEAD^{tree}")[1]


# ══════════════════════════════════════════════════════════════════════
#  the edits: exactly the lines the inventory pointed at
# ══════════════════════════════════════════════════════════════════════
class RefusedEdit(Exception):
    """The line did not read the way the inventory said it would."""


def rewrite(root, pin, version=None, digest=None):
    """Write a new version (and/or digest) where this pin is written.

    The edit goes to THE LINES `pins.read` recorded and to no others,
    and it replaces the token it was told is there. If the line does not
    carry that token any more, the edit is REFUSED: between an inventory
    that has gone stale and a write into a file whose shape nobody
    checked, the only safe answer is to stop. This is the same rule the
    console's forms follow — an edit changes what you changed and
    nothing else (check 201).

    Returns the list of files touched.
    """
    if version is None and digest is None:
        raise RefusedEdit(f"{pin.key}: an edit was asked for that changes nothing")
    if version is not None and not pin.current:
        raise RefusedEdit(f"{pin.key}: it carries no version to replace "
                          f"(it is pinned by digest alone, or the reader lost it)")
    touched = []
    for rel, lineno in pin.where:
        f = pathlib.Path(root) / rel
        if not f.is_file():
            raise RefusedEdit(f"{pin.key}: {rel} is not there any more")
        lines = f.read_text(encoding="utf-8").splitlines(keepends=True)
        if not 1 <= lineno <= len(lines):
            raise RefusedEdit(f"{pin.key}: {rel} has no line {lineno} any more "
                              f"({len(lines)} lines) — the inventory is stale")
        line = lines[lineno - 1]
        new = line
        if version is not None:
            if pin.current not in new:
                raise RefusedEdit(
                    f"{pin.key}: {rel}:{lineno} does not carry «{pin.current}» any more. "
                    f"The line says: {line.strip()[:120]}")
            # The LAST occurrence, not the first: a reference like
            # `registry:5000/thing:1.2.3` carries the same digits twice
            # often enough, and the version is the one at the end.
            head_, _, tail = new.rpartition(pin.current)
            new = head_ + version + tail
        if digest is not None:
            if pin.digest:
                if pin.digest not in new:
                    raise RefusedEdit(
                        f"{pin.key}: {rel}:{lineno} does not carry the digest the "
                        f"inventory read. The line says: {line.strip()[:120]}")
                new = new.replace(pin.digest, digest)
            else:
                raise RefusedEdit(f"{pin.key}: it is not pinned by digest, so there is "
                                  f"no digest here to replace")
        if new == line:
            raise RefusedEdit(f"{pin.key}: {rel}:{lineno} would not change "
                              f"(it already says what was asked for)")
        lines[lineno - 1] = new
        # Written whole and in place, keeping every other byte of the
        # file: comments, blank lines and the margins somebody wrote by
        # hand are not this command's to reflow.
        f.write_text("".join(lines), encoding="utf-8")
        touched.append(rel)
    return touched


# ══════════════════════════════════════════════════════════════════════
#  the photo, and what «a new failure» means
# ══════════════════════════════════════════════════════════════════════
_HEX = re.compile(r"\b[0-9a-f]{7,}\b")
_NUM = re.compile(r"\d+")
_DUR = re.compile(r"\b\d+(?:\.\d+)?\s*(?:ms|s|m|h|d|días|dias|day|days)\b", re.I)


def normalize(text):
    """The stable half of a measure's sentence.

    The round narrates with live numbers in it — «3 of 7 pods have
    restarted», «the certificate expires in 62 days». Comparing those
    literally would call every single measure «new» and the comparison
    would be worthless. So digits, hexadecimal and durations are flattened
    and what is left is the SHAPE of the sentence, which is what actually
    identifies the measure. The values are still in the document; what is
    normalised is only the key the two photos are matched on.
    """
    t = _DUR.sub("«duration»", text.strip())
    t = _HEX.sub("«hex»", t)
    t = _NUM.sub("N", t)
    return " ".join(t.split())


def readings(round_doc):
    """{(section, shape) -> state} out of an `aegis check --json` document."""
    out = {}
    for sec in (round_doc or {}).get("steps", []):
        name = sec.get("step") or "?"
        for m in sec.get("measures", []):
            out[(name, normalize(m.get("measure") or ""))] = m.get("state") or "not-evaluated"
    return out


#: the three states a reading can be in, worst first. `bad` is a
#: failure; `not-evaluated` is the round saying it could not look, which
#: is NOT a failure by itself but IS one when it replaces a good reading.
BAD, BLIND, FINE = "bad", "not-evaluated", "good"

#: How bad each state is, worst first, over BOTH vocabularies a document
#: can carry: the round's own words and the house's four. Higher is
#: better. `not-evaluated` is the floor, below `bad`, for the same
#: reason it outranks it everywhere else here — a thing known to be
#: broken is better news than a thing nobody could look at.
RANK = {"not-evaluated": 0, "not-evaluable": 0,
        "bad": 1, "wrong": 1,
        "notice": 2,
        "good": 3, "done": 3, "already": 3}


def got_worse(before_state, after_state):
    """Did this reading get worse, in either vocabulary?

    THE FIRST VERSION ASKED «DID SOMETHING GREEN STOP BEING GREEN», and
    on the instance that found it, nothing green was involved. The
    round's line about the public sites was already a NOTICE —two of
    five answer with a redirect the probe refuses, because they sit
    behind their own login— so raising a page over all five turned a
    notice into a failure, and a rule watching only green never looked
    at it. Three windows in a row stopped saying the page had done
    nothing while it was demonstrably up.

    A reading that vanishes counts as worse: it was measurable and is
    not any more.
    """
    if after_state is None:
        return True
    return RANK.get(after_state, 0) < RANK.get(before_state, 0)


def compare(before, after):
    """What changed between two rounds, in the only vocabulary that matters.

    A NEW FAILURE is a reading that is bad now and was not bad before,
    OR one that was fine before and that nobody could measure now. The
    second half is the one that is easy to leave out and the one that
    matters most: a window that blinds a measurement has not passed it,
    it has stopped asking. A reading that disappears entirely counts the
    same way, for the same reason.

    What already came in broken is listed apart and does not block:
    holding a window hostage to a fault that predates it means the
    instance never gets updated at all.
    """
    b, a = readings(before), readings(after)
    new, blinded, already, fixed = [], [], [], []
    for key, was in b.items():
        now = a.get(key)
        if now is None:
            if was != BAD:
                blinded.append({"seccion": key[0], "medida": key[1], "antes": was,
                                "ahora": "the round no longer takes this measurement"})
            continue
        if now == BAD and was != BAD:
            new.append({"seccion": key[0], "medida": key[1], "antes": was, "ahora": now})
        elif now == BLIND and was == FINE:
            blinded.append({"seccion": key[0], "medida": key[1], "antes": was, "ahora": now})
        elif now == BAD and was == BAD:
            already.append({"seccion": key[0], "medida": key[1]})
        elif was == BAD and now == FINE:
            fixed.append({"seccion": key[0], "medida": key[1]})
    for key, now in a.items():
        if key not in b and now == BAD:
            new.append({"seccion": key[0], "medida": key[1], "antes": "did not exist",
                        "ahora": now})
    return {"nuevos": new, "cegados": blinded, "ya_venian": already, "arreglados": fixed,
            "medidas_antes": len(b), "medidas_despues": len(a)}


def accepted(cmp_):
    """The verdict of a comparison, and it has two halves on purpose."""
    return not cmp_["nuevos"] and not cmp_["cegados"]


class CouldNotPhotograph(Exception):
    """The photo is missing a half. A window does not open on half a photo."""


def photograph(platform=None, with_verify=True, narrate=True):
    """What this instance looks like right now, in one document.

    Four readings and a sha. Every one of them is DEMANDED: a photo with
    a hole in it is not a photo, it is the absence of the very evidence
    the rollback will be judged against, and discovering the hole after
    the change is discovering it too late.
    """
    root = pathlib.Path(platform) if platform else paths.platform_dir()
    doc = {"taken_at": datetime.datetime.now(datetime.timezone.utc)
           .isoformat(timespec="seconds"), "platform": str(root)}
    if narrate:
        _say("the round…")
    try:
        rc, round_doc = cli.run_json("check")
    except cli.CouldNotEvaluate as e:
        raise CouldNotPhotograph(f"the round could not be taken: {e}")
    doc["round"] = {"rc": rc, "failures": round_doc.get("failures"),
                    "notices": round_doc.get("notices"), "doc": round_doc}
    if with_verify:
        if narrate:
            _say("verify, both profiles…")
        v = _verify()
        doc["verify"] = v
        if v["rc"] == 2:
            raise CouldNotPhotograph("verify could not be run: without it there is no "
                                     "before to compare the artifact against")
    if narrate:
        _say("the inventory…")
    try:
        rc, inv = cli.run_json("update", "inventory")
    except cli.CouldNotEvaluate as e:
        raise CouldNotPhotograph(f"the inventory could not be taken: {e}")
    doc["inventory"] = {"rc": rc, "doc": inv}
    # WHAT THE WORLD SEES, taken as part of the photo. It is the only
    # reading here that comes from OUTSIDE this machine, and it is the
    # one the maintenance page is judged against: the round measures the
    # origin, and the page lives at the edge.
    if narrate:
        _say("what the public sites answer…")
    doc["sitios"] = reach(public_urls(root))
    try:
        doc["head"] = head(root)
        doc["tree"] = tree_hash(root)
    except GitTrouble as e:
        raise CouldNotPhotograph(f"the platform repo could not be read: {e}")
    return doc


def _verify():
    root = paths.aegis_root()
    exe = root / "libexec" / "aegis-verify"
    if not exe.exists():
        return {"rc": 2, "why": "aegis verify is not in this product"}
    r = subprocess.run([str(exe), "--profile", "both"], capture_output=True,
                       text=True, timeout=3600)
    tail = "\n".join((r.stdout or "").splitlines()[-25:])
    return {"rc": r.returncode, "tail": tail}


def _say(msg):
    import sys
    print(f"\033[90m  {msg}\033[0m" if sys.stderr.isatty() else f"  {msg}", file=sys.stderr)


# ══════════════════════════════════════════════════════════════════════
#  the maintenance hooks
# ══════════════════════════════════════════════════════════════════════
class Hooks:
    """The two orders the operator gave, and the measurement of the first.

    The product knows nothing about what is behind them, on purpose (a
    Worker, an nginx 503, a DNS flip). What it does know is that a
    maintenance page nobody can see is worse than none at all, so
    raising it is FOLLOWED BY A READING: if the public sites keep
    answering, the hook did not do what it says and the window stops
    having changed nothing.
    """

    def __init__(self, conf=None):
        c = conf if conf is not None else paths.read_conf()
        self.on = (c.get("MAINTENANCE_ON") or "").strip()
        self.off = (c.get("MAINTENANCE_OFF") or "").strip()

    @property
    def configured(self):
        return bool(self.on and self.off)

    @property
    def coherent(self):
        """Both or neither. One of the two is a trap, in either
        direction: a way in with no way out leaves the sites behind the
        page, and a way out with no way in is a promise the window would
        read as «there is a page» when there is none."""
        return bool(self.on) == bool(self.off)

    def run(self, which, timeout=600):
        cmdline = self.on if which == "on" else self.off
        if not cmdline:
            return {"hook": which, "ran": False, "why": "no command is configured"}
        t0 = time.time()
        r = subprocess.run(["bash", "-lc", cmdline], capture_output=True, text=True,
                           timeout=timeout)
        return {"hook": which, "ran": True, "rc": r.returncode,
                "seconds": round(time.time() - t0, 1),
                "salida": "\n".join((r.stdout or "").splitlines()[-12:]),
                "error": "\n".join((r.stderr or "").splitlines()[-12:])}


def probe_interval(platform=None, fallback=30):
    """How often the tenant probes actually run, read from the config the
    platform deploys.

    DERIVED, because a number written here would be a second copy of a
    decision that lives in vmagent's values, and the day somebody moves
    it this would keep saying the old one. When it cannot be read the
    fallback is used AND said out loud by the caller: guessing quietly
    is how the page ends up being judged before anybody could see it.
    """
    root = pathlib.Path(platform) if platform else paths.platform_dir()
    f = root / "k8s" / "base" / "observability" / "vmagent" / "values.yaml"
    if not f.is_file():
        return None
    m = re.search(r"^\s*scrape_interval:\s*(\d+)\s*([smh])\s*$",
                  f.read_text(encoding="utf-8"), re.M)
    if not m:
        return None
    return int(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2)]


def probe_interval_or_guess(platform=None, fallback=30):
    """The interval, and whether it was measured or guessed.

    TWO RETURN VALUES ON PURPOSE. A caller handed a bare number cannot
    tell the config's answer from a default, and a silent default about
    WHEN to measure is exactly how the first real window came to stop
    for a reason that was not true. The note is None when it was read.
    """
    got = probe_interval(platform)
    if got:
        return got, None
    return fallback, (f"the probes' interval could not be read from the platform: "
                      f"waiting as if it were {fallback}s, which is a guess and is said "
                      f"out loud rather than made quietly")


def public_urls(platform=None):
    """The hostnames this instance publishes, from the contracts.

    From the contracts and not from the round's sentences: the round
    narrates for people and its wording is allowed to change, and a
    command that decided anything by grepping that prose would be A3 of
    the register all over again.
    """
    d = (pathlib.Path(platform) / "orgs") if platform else paths.orgs_dir()
    if not d.is_dir():
        return []
    out = []
    for f in sorted(d.glob("*.yaml")):
        try:
            for line in f.read_text(encoding="utf-8").splitlines():
                m = re.match(r"^dominio:\s*(\S+)", line)
                if m:
                    out.append("https://" + m.group(1).strip().strip("\"'") + "/")
                    break
        except OSError:
            continue
    return out


def reach(urls, timeout=12):
    """What each public URL answers, asked from OUTSIDE. `None` when
    nothing answered at all, which is a different thing from a status
    code and is kept different."""
    import urllib.error
    import urllib.request
    out = {}
    for url in urls:
        req = urllib.request.Request(url, method="GET",
                                     headers={"User-Agent": "aegis-update/1"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                out[url] = r.status
        except urllib.error.HTTPError as e:
            out[url] = e.code
        except Exception:                                 # noqa: BLE001
            out[url] = None
    return out


def effect_of_page(before_codes, look, interval=5, tries=6, sleep=time.sleep):
    """Did raising the maintenance page change what the world sees?

    IT ASKS THE SITES, and it took four windows to get here. The first
    three versions asked the ROUND, and the round is the wrong
    instrument for this in a way worth writing down rather than
    rediscovering:

      · it measures the ORIGIN, through probes that run every thirty
        seconds, so it answers about a world up to a minute old;
      · its readings are keyed on the SHAPE of a sentence with the
        digits flattened, because that is what makes two rounds
        comparable at all — and «1 of the 5 public site(s) do not
        answer» and «5 of the 5» are then the same key with the same
        state. The page's whole effect is that number.

    So this asks the URLs themselves, from the machine the window runs
    on, through the edge, which is where the page lives. What it demands
    is only that SOMETHING CHANGED: aegis knows nothing about what the
    operator's page returns, and two of this instance's sites answer 302
    on an ordinary day because they sit behind their own login. The
    weakest true statement is the right one here.

    `look` and `sleep` are injectable, so check 218 drives all of it in
    milliseconds with no network.
    """
    if not before_codes:
        return {"efecto": None, "sitios": 0,
                "por_que": "no contract of this instance declares a domain: there is "
                           "nothing for the page to take off the air, so its effect "
                           "cannot be read"}
    for n in range(1, tries + 1):
        # BEFORE the first look, not only between retries: the edge does
        # not pick a deployment up instantly.
        sleep(interval)
        after = look()
        changed = {u: (before_codes.get(u), c) for u, c in after.items()
                   if before_codes.get(u) != c}
        if changed:
            return {"efecto": True, "intentos": n, "sitios": len(before_codes),
                    "cambiaron": len(changed),
                    "detalle": [{"url": u, "antes": a, "ahora": b}
                                for u, (a, b) in sorted(changed.items())][:6]}
    return {"efecto": False, "intentos": tries, "sitios": len(before_codes),
            "cambiaron": 0,
            "antes": {u: c for u, c in sorted(before_codes.items())},
            "por_que": f"the page was raised and after {tries} look(s) every public site "
                       f"still answers exactly what it answered before"}


class Journal:
    """Everything one window did, written down as it happens.

    Written AS IT HAPPENS and not at the end, because the runs worth
    reading afterwards are the ones that did not reach the end. A
    journal assembled in memory and flushed on the way out says nothing
    about the window that was killed in the middle of layer four, which
    is precisely the window somebody will be reading about.
    """

    def __init__(self, wid=None, home=None):
        self.id = wid or new_id()
        self.dir = updates_dir(home) / self.id
        self.root = updates_dir(home)

    def open(self, before, note=None):
        self.dir.mkdir(parents=True, exist_ok=True)
        (self.dir / BEFORE).write_text(json.dumps(before, ensure_ascii=False, indent=1),
                                       encoding="utf-8")
        # `last` points at this one from the moment it opens, not when
        # it ends: a window that dies in the middle has to be findable.
        (self.root / "last").write_text(self.id, encoding="utf-8")
        self.note("open", nota=note or "")
        return self

    def note(self, kind, **data):
        self.dir.mkdir(parents=True, exist_ok=True)
        entry = {"at": datetime.datetime.now(datetime.timezone.utc)
                 .isoformat(timespec="seconds"), "kind": kind, **data}
        with (self.dir / DIARY).open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
        return entry

    def entries(self):
        f = self.dir / DIARY
        if not f.is_file():
            return []
        out = []
        for line in f.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    out.append({"kind": "unreadable", "raw": line[:200]})
        return out

    def commits(self):
        """Every commit this window made, oldest first. This is the list
        a rollback walks backwards and the list check 212 demands the
        report account for."""
        return [e for e in self.entries() if e.get("kind") == "commit" and e.get("sha")]

    def page_is_up(self):
        """Did this window raise the maintenance page and never record
        taking it down?

        DERIVED FROM WHAT IS WRITTEN, not from a second marker file: the
        journal already records every hook with its exit code, and a
        flag beside it would be the one thing that disagrees with the
        record on the morning after.

        WHY IT MATTERS, with a date on it. On 2026-09-20 a window was
        killed outright while it was measuring — no signal it could
        handle, so the exit trap never ran. The silences it had raised
        expired on their own, which is why they carry an expiry. The
        backup clock and Jenkins came back by other means. The PAGE has
        no expiry and nothing noticed: the operator's five sites served
        503 until a human happened to look.
        """
        up = False
        for e in self.entries():
            if e.get("kind") != "maintenance" or e.get("rc") != 0:
                continue
            if e.get("hook") == "on":
                up = True
            elif e.get("hook") == "off":
                up = False
        return up

    def close(self, outcome, **data):
        if outcome not in OUTCOMES:
            raise ValueError(f"unknown outcome: {outcome!r} (one of {OUTCOMES})")
        report = {"window": self.id, "outcome": outcome,
                  "closed_at": datetime.datetime.now(datetime.timezone.utc)
                  .isoformat(timespec="seconds"),
                  # Named one by one and not counted: a report that says
                  # «4 commits» and does not say which four cannot be
                  # acted on by the person reading it at midnight.
                  "commits": [{"sha": c["sha"], "subject": c.get("subject", ""),
                               "pin": c.get("pin", ""), "layer": c.get("layer")}
                              for c in self.commits()],
                  **data}
        (self.dir / REPORT).write_text(json.dumps(report, ensure_ascii=False, indent=1),
                                       encoding="utf-8")
        self.note("close", outcome=outcome)
        return report

    def report(self):
        f = self.dir / REPORT
        if not f.is_file():
            return None
        return json.loads(f.read_text(encoding="utf-8"))

    def before(self):
        f = self.dir / BEFORE
        if not f.is_file():
            return None
        return json.loads(f.read_text(encoding="utf-8"))

    @classmethod
    def last(cls, home=None):
        f = updates_dir(home) / "last"
        if not f.is_file():
            return None
        wid = f.read_text(encoding="utf-8").strip()
        if not wid:
            return None
        j = cls(wid, home)
        return j if j.dir.is_dir() else None


# ══════════════════════════════════════════════════════════════════════
#  the refusals: everything that has to be true BEFORE the first hook
# ══════════════════════════════════════════════════════════════════════
class Refusal:
    """One reason this window will not open, and what to do about it."""

    def __init__(self, name, why, remedy=""):
        self.name, self.why, self.remedy = name, why, remedy

    def as_data(self):
        return {"rechazo": self.name, "por_que": self.why, "remedio": self.remedy}

    def __repr__(self):
        return f"<Refusal {self.name}>"


def preflight(platform=None, conf=None, hooks=None, budget_minutes=240):
    """Every reason to stop, collected before anything is touched.

    ALL of them, not the first one: an operator who fixes one refusal
    and runs again only to meet the next is being made to discover the
    list one night at a time. The window runs this once, prints
    everything, and does not proceed while the list is not empty.
    """
    root = pathlib.Path(platform) if platform else paths.platform_dir()
    hooks = hooks if hooks is not None else Hooks(conf)
    out = []
    if not root.is_dir():
        out.append(Refusal("platform-missing", f"{root} is not there: this instance has "
                                               f"no platform repo to edit",
                           "run the init, or point PLATFORM_DIR at the checkout"))
        return out
    if not is_repo(root):
        out.append(Refusal("platform-not-a-repo", f"{root} is not a git repository, and "
                                                  f"a window's way back is git",
                           "clone the platform repo into that path"))
        return out
    try:
        d = dirty(root)
        if d:
            out.append(Refusal(
                "platform-dirty",
                f"{len(d)} uncommitted change(s) in the platform repo. A window commits "
                f"file by file, and work that was already there would ride into a commit "
                f"the rollback then reverts",
                f"commit or stash them first: {'; '.join(d[:4])}"))
    except GitTrouble as e:
        out.append(Refusal("platform-unreadable", str(e), "check the repo by hand"))
    try:
        ahead = unpushed(root)
        if ahead:
            out.append(Refusal(
                "platform-unpushed",
                f"{len(ahead)} commit(s) here that the remote does not have. The cluster "
                f"converges on the remote, so the acceptance would measure a platform "
                f"nobody deployed",
                "git push, and let ArgoCD settle before opening the window"))
    except GitTrouble as e:
        out.append(Refusal("platform-untracked-branch", str(e),
                           "set an upstream for this branch"))
    if not hooks.coherent:
        which = "MAINTENANCE_ON" if hooks.on else "MAINTENANCE_OFF"
        out.append(Refusal(
            "maintenance-half-configured",
            f"{which} carries a command and the other one is empty. A way in with no way "
            f"out leaves your sites behind the page until somebody notices",
            f"write both in {paths.conf()}, or neither"))
    if budget_minutes is not None and budget_minutes < 30:
        out.append(Refusal(
            "budget-too-small",
            f"{budget_minutes} minute(s) is not a window: the photo alone takes longer "
            f"than that on a cold instance, and a window that runs out of time between "
            f"two layers is the one shape this protocol exists to prevent",
            "give it at least 30, and four hours is the default for a reason"))
    return out


# ══════════════════════════════════════════════════════════════════════
#  the way back
# ══════════════════════════════════════════════════════════════════════
def roll_back(journal, platform=None, narrate=True):
    """Undo a window's commits, newest first.

    NEWEST FIRST, and it is not a detail: two commits that touch the
    same file only revert cleanly in the reverse of the order they were
    made. And every one of them is reverted with `git revert`, so the
    history keeps saying what happened — an instance that cannot answer
    «what did last month's window do» has lost the only record there
    was.

    It returns what it undid and what it could not, and a single commit
    that does not come back cleanly stops the walk: reverting past a
    conflict would leave the tree in a state neither the window nor the
    operator ever described.
    """
    root = pathlib.Path(platform) if platform else paths.platform_dir()
    done, stuck = [], None
    for entry in reversed(journal.commits()):
        sha = entry["sha"]
        try:
            new = revert(root, sha)
        except GitTrouble as e:
            stuck = {"sha": sha, "subject": entry.get("subject", ""), "por_que": str(e)}
            journal.note("rollback-stuck", **stuck)
            break
        done.append({"sha": sha, "subject": entry.get("subject", ""), "revert": new})
        journal.note("revert", of=sha, sha=new, subject=entry.get("subject", ""))
        if narrate:
            _say(f"reverted {sha[:12]}  {entry.get('subject', '')[:60]}")
    return {"deshechos": done, "atascado": stuck,
            "quedan": len(journal.commits()) - len(done)}


def came_back_to(journal, platform=None):
    """Did the tree come back to exactly what the photo saw?

    The comparison is against the TREE hash and not the commit: after a
    rollback the HEAD is necessarily a different commit (the reverts are
    commits too), and the only honest question is whether the content is
    the same. A rollback that says «done» while one file stayed changed
    is the failure this answers.
    """
    root = pathlib.Path(platform) if platform else paths.platform_dir()
    before = journal.before() or {}
    want = before.get("tree")
    if not want:
        return {"igual": None, "por_que": "the photo recorded no tree hash: nobody can "
                                          "say what «the same» would be"}
    got = tree_hash(root)
    return {"igual": got == want, "antes": want, "ahora": got}


# ══════════════════════════════════════════════════════════════════════
#  the layers
# ══════════════════════════════════════════════════════════════════════
#
# A window does not apply fifty changes and then ask how it went. It
# goes in layers, ground first, and after each one it asks the sections
# of the round that layer could have broken. A layer that breaks
# something is undone ON ITS OWN, the walk stops, and everything below
# it stays: an instance with four of nine layers raised and green is a
# better place to be than one that raised all nine and cannot say which
# of them hurt.
#
# WHAT IS WRITTEN HERE AND WHY IT IS NOT DERIVED. The order, the
# acceptance and the way back of each layer are properties of the
# PROTOCOL, not of the tree: no file in the platform says that charts
# come after k3s, or that the pod templates of the CI are judged by
# whether pushes still build. The tree is what says which pins exist,
# and that is read every time. Check 213 joins the two: every class the
# inventory can produce is owned by exactly one layer, and every section
# a layer judges itself by is a section the round actually has.


class Layer:
    """One layer: what it changes, what judges it, how it comes undone."""

    def __init__(self, number, name, classes, sections, undo, minutes, note=""):
        self.number = number
        self.name = name
        self.classes = tuple(classes)
        #: the round's own section names. The acceptance of a layer is
        #: «no new failure IN THESE», which is what lets layer 4 be
        #: judged without waiting for a section layer 8 owns.
        self.sections = tuple(sections)
        self.undo = undo
        #: what it is expected to cost, for the budget. An estimate, and
        #: it is used only to refuse to START a layer there is no time
        #: for — never to cut one short.
        self.minutes = minutes
        self.note = note

    def as_data(self):
        return {"capa": self.number, "nombre": self.name, "clases": list(self.classes),
                "secciones": list(self.sections), "deshacer": self.undo,
                "minutos": self.minutes}

    def __repr__(self):
        return f"<Layer {self.number} {self.name}>"


LAYERS = (
    Layer(1, "the host's packages", ("apt",), ("node", "pods"),
          "nothing: a package installed is not uninstalled inside a window", 20,
          "refused outright when the round came in red: with no way back, the only "
          "protection is not to start"),
    Layer(2, "the host's binaries", ("userland",), ("node", "supply chain"),
          "revert the pin and re-run phase 05 with AEGIS_HOST_ALIGN=1", 15),
    Layer(3, "k3s", ("k3s",), ("node", "pods", "argocd"),
          "revert and re-run phase 20; best effort, and the node's name is watched", 25,
          "patches only. A minor rewrites the service's ExecStart and the node "
          "re-registers under another name"),
    Layer(4, "the platform's charts", ("chart",),
          ("argocd", "stuck syncs", "pods", "certificates"),
          "revert the targetRevision and sync", 60,
          "one at a time, in dependency order, and each one is rendered against its "
          "repo before a line is written"),
    Layer(5, "the images written by hand", ("raw-image",), ("pods", "argocd"),
          "revert the image: and sync", 25),
    Layer(6, "the mirrored images", ("mirror",), ("supply chain",),
          "revert the line of images.txt; the registry keeps the previous digest", 30,
          "needs Jenkins out of quiet mode: this one builds"),
    Layer(7, "the bases aegis owns", ("containerfile",), ("supply chain", "CI quota"),
          "revert the FROM and rebuild, which re-propagates", 45,
          "needs Jenkins out of quiet mode: this one builds"),
    Layer(8, "the CI's pod templates", ("jenkinsfile",),
          ("every push built", "CI webhooks"),
          "revert; every file in one commit", 20),
    Layer(9, "the kernel and the graphics driver", (),
          ("node",),
          "nothing, and nothing is restarted either", 20,
          "only with --kernel. It installs and NEVER reboots: the reboot is a "
          "decision with a human in it"),
)
LAYER_BY_CLASS = {c: l for l in LAYERS for c in l.classes}
#: Layers that cannot run while Jenkins is quiet, because they build.
LAYERS_THAT_BUILD = (6, 7)


class Budget:
    """The window's clock, and the only thing it is allowed to do.

    It NEVER cuts a layer short — stopping a chart sync halfway is worse
    than any delay it could save. What it does is refuse to START a
    layer there is no time for, which is a decision taken while
    everything is still whole.
    """

    def __init__(self, minutes=240, started=None):
        self.minutes = minutes
        self.started = started if started is not None else time.time()

    @property
    def spent(self):
        return (time.time() - self.started) / 60.0

    @property
    def left(self):
        return self.minutes - self.spent

    def room_for(self, layer):
        return self.left >= layer.minutes

    def as_data(self):
        return {"presupuesto_min": self.minutes, "gastado_min": round(self.spent, 1),
                "queda_min": round(self.left, 1)}


# ══════════════════════════════════════════════════════════════════════
#  what the window changes ABOUT THE MACHINE, and must put back
# ══════════════════════════════════════════════════════════════════════
class Restore:
    """A stack of things to put back, run on every way out.

    Every way out, including the ones nobody planned. A window silences
    an alert, stops a timer and quiets Jenkins; if it dies between two
    layers and those three stay as it left them, the instance is
    permanently deaf about the sites, has no backups, and builds
    nothing — and none of that announces itself, which is the point.

    It runs ALL of them and reports each. Stopping at the first failure
    would leave the rest undone for the sake of tidiness.
    """

    def __init__(self):
        self._items = []

    def push(self, name, undo, what=""):
        self._items.append({"name": name, "undo": undo, "what": what})

    def __len__(self):
        return len(self._items)

    def run(self):
        out = []
        while self._items:
            item = self._items.pop()
            try:
                item["undo"]()
                out.append({"restored": item["name"], "ok": True, "what": item["what"]})
            except Exception as e:                        # noqa: BLE001
                out.append({"restored": item["name"], "ok": False,
                            "what": item["what"], "error": f"{type(e).__name__}: {e}"})
        return out


def _kubectl(*args, timeout=60):
    r = subprocess.run(["kubectl", *args], capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()


def service_endpoint(ns, name):
    """`<ip>:<port>` of a Service, the way the round reads it. None when
    nobody could ask, which is never the same as «it is not there»."""
    rc, ip, _ = _kubectl("get", "svc", "-n", ns, name, "-o",
                         "jsonpath={.spec.clusterIP}")
    if rc != 0:
        return None
    if not ip or ip == "None":
        rc, ip, _ = _kubectl("get", "endpoints", "-n", ns, name, "-o",
                             "jsonpath={.subsets[0].addresses[0].ip}")
        if rc != 0 or not ip:
            return None
    rc, port, _ = _kubectl("get", "svc", "-n", ns, name, "-o",
                           "jsonpath={.spec.ports[0].port}")
    if rc != 0 or not port:
        return None
    return f"{ip}:{port}"


#: The alerts a window silences, and NOT one more. They are the ones
#: whose whole subject is «a public site does not answer», which is
#: exactly what the maintenance page makes true on purpose.
SILENCEABLE = ("SitioDeInquilinoCaido", "SitioDeInquilinoSinSonda", "RegistryProbeFalla")
#: The heartbeat is NEVER silenced. It is the alert that fires when the
#: alerting itself stops working, and a window is precisely when that
#: would be easiest to miss.
NEVER_SILENCED = ("DeadmanAegis",)


class Silences:
    """The window's silence in Alertmanager, and its removal.

    It carries an end time of its own so that a window which dies
    without cleaning up goes deaf for the length of the window and not
    for ever. The restore stack is the first line of defence; the
    expiry is the second, and a protocol that leans on only one of the
    two eventually meets the day that one failed.
    """

    def __init__(self, hours=6):
        self.hours = hours
        self.ids = []
        self.endpoint = None

    def raise_(self, window_id):
        import urllib.request
        self.endpoint = service_endpoint("observability", "alertmanager")
        if not self.endpoint:
            return {"silenciado": False,
                    "por_que": "alertmanager could not be reached: the window runs and "
                               "the alerts about the sites will fire. That is noise, not "
                               "damage, and it is said out loud rather than skipped"}
        now = datetime.datetime.now(datetime.timezone.utc)
        end = now + datetime.timedelta(hours=self.hours)
        for name in SILENCEABLE:
            if name in NEVER_SILENCED:
                continue
            body = json.dumps({
                "matchers": [{"name": "alertname", "value": name,
                              "isRegex": False, "isEqual": True}],
                "startsAt": now.isoformat(timespec="seconds"),
                "endsAt": end.isoformat(timespec="seconds"),
                "createdBy": f"aegis update window {window_id}",
                "comment": f"update window {window_id}: the maintenance page is up on "
                           f"purpose. Expires by itself at {end.isoformat(timespec='minutes')}",
            }).encode()
            req = urllib.request.Request(f"http://{self.endpoint}/api/v2/silences",
                                         data=body,
                                         headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    self.ids.append(json.loads(r.read().decode()).get("silenceID"))
            except Exception as e:                        # noqa: BLE001
                return {"silenciado": False, "puestos": len(self.ids),
                        "por_que": f"{name}: {type(e).__name__}: {e}"}
        return {"silenciado": True, "puestos": len(self.ids),
                "expiran": end.isoformat(timespec="minutes")}

    def lift(self):
        import urllib.request
        if not self.endpoint:
            return {"levantados": 0}
        n = 0
        for sid in self.ids:
            if not sid:
                continue
            req = urllib.request.Request(
                f"http://{self.endpoint}/api/v2/silence/{sid}", method="DELETE")
            try:
                with urllib.request.urlopen(req, timeout=20):
                    n += 1
            except Exception:                             # noqa: BLE001
                pass
        return {"levantados": n, "de": len(self.ids)}


def timer_stop(unit="aegis-backup.timer"):
    """Stop a timer for the length of the window, and say which scope it
    was in so the restore puts back exactly that.

    The backup timer firing in the middle of a window would capture an
    instance that is half updated and call it the day's backup — and
    that is the copy somebody would restore from.
    """
    # BOTH scopes, in this order. On the author's instance the backup
    # timer is a USER unit (it was installed by hand on 2026-09-16,
    # because no phase installs the units in share/systemd/); on an
    # instance where a phase eventually does, it will be a system one.
    # Asking the wrong one and reporting «there was nothing to stop»
    # would be the silent half of this whole class of bug.
    for scope in ("--user", "--system"):
        r = subprocess.run(["systemctl", scope, "is-active", unit],
                           capture_output=True, text=True, timeout=30)
        if (r.stdout or "").strip() == "active":
            s = subprocess.run(["systemctl", scope, "stop", unit],
                               capture_output=True, text=True, timeout=60)
            if s.returncode != 0:
                return {"parado": False, "unidad": unit, "ambito": scope,
                        "por_que": (s.stderr or "").strip()[:200]}
            return {"parado": True, "unidad": unit, "ambito": scope}
    return {"parado": False, "unidad": unit,
            "por_que": "the timer is not active in either scope: there was nothing to stop"}


def timer_start(unit, scope):
    r = subprocess.run(["systemctl", scope, "start", unit],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(f"{unit} ({scope}) did not start again: "
                           f"{(r.stderr or '').strip()[:200]}")


# ══════════════════════════════════════════════════════════════════════
#  the acceptance of one layer
# ══════════════════════════════════════════════════════════════════════
def accept_layer(layer, before_doc, after_doc):
    """A layer is judged by its OWN sections, and by the same rule as the
    window: nothing that worked stopped working, and nothing that was
    measured stopped being measurable.

    Judging a layer by the whole round would make every layer answer for
    a fault the one before it left behind, and the walk would stop at
    the wrong place — which is worse than not stopping, because the
    rollback would undo something that was not the cause.
    """
    cmp_ = compare(before_doc, after_doc)
    mine = set(layer.sections)
    new = [n for n in cmp_["nuevos"] if n["seccion"] in mine]
    blind = [n for n in cmp_["cegados"] if n["seccion"] in mine]
    return {"capa": layer.number, "acepta": not new and not blind,
            "nuevos": new, "cegados": blind,
            "secciones": sorted(mine),
            "fuera_de_capa": len(cmp_["nuevos"]) - len(new)}


def argo_settled(app, timeout=900, poll=10, narrate=False):
    """Wait for an Application to be Synced AND Healthy.

    Both, and a timeout that counts as RED. «Synced» alone means git and
    the cluster agree about the manifests; it says nothing about whether
    what came up works, and a chart that rolls out a pod that crash-loops
    is Synced for as long as anyone cares to watch.
    """
    t0 = time.time()
    last = {}
    while time.time() - t0 < timeout:
        rc, out, _ = _kubectl("get", "application", app, "-n", "argocd", "-o",
                              "jsonpath={.status.sync.status}|{.status.health.status}")
        if rc != 0:
            return {"asentado": None, "app": app,
                    "por_que": "the Application could not be read: this is «could not "
                               "look», not «it is not ready»"}
        sync, _, health = out.partition("|")
        last = {"sync": sync, "health": health}
        if sync == "Synced" and health == "Healthy":
            return {"asentado": True, "app": app, "segundos": round(time.time() - t0),
                    **last}
        if narrate:
            _say(f"{app}: {sync}/{health}…")
        time.sleep(poll)
    return {"asentado": False, "app": app, "segundos": round(time.time() - t0), **last,
            "por_que": "it did not reach Synced+Healthy inside the wait. A wait that "
                       "ran out is a failure, never a «probably fine»"}


def argo_all_settled(timeout=900, poll=15, narrate=False):
    """Wait until EVERY Application is Synced and Healthy.

    A SYNC IS A REQUEST, NOT AN ARRIVAL, and that is what cost a window
    its verdict on 2026-09-20. Layer 5 bumped seven images written by
    hand, asked ArgoCD to converge, and judged at once — but bumping
    `busybox` and `curl` changes the init containers of half the
    platform, so Jenkins was rolling while the round was being taken,
    and a Jenkins that is restarting has «no build at all» on every one
    of its fourteen jobs. The window called that damage and stopped.
    Nothing was wrong: the instance healed itself in four minutes.

    A timeout counts as NOT settled, never as settled: a wait that ran
    out is the one case where carrying on is guaranteed to measure the
    wrong world.
    """
    t0 = time.time()
    last = []
    while time.time() - t0 < timeout:
        rc, out, _ = _kubectl(
            "get", "applications", "-n", "argocd", "-o",
            "jsonpath={range .items[*]}{.metadata.name}|{.status.sync.status}|"
            "{.status.health.status}{\"\\n\"}{end}")
        if rc != 0:
            return {"asentado": None, "por_que": "the Applications could not be read: "
                                                 "this is «could not look», not «it is "
                                                 "not ready»"}
        last = [ln.split("|") for ln in out.splitlines() if ln.strip()]
        unsettled = [a for a in last if len(a) == 3 and (a[1] != "Synced" or a[2] != "Healthy")]
        if not unsettled:
            return {"asentado": True, "apps": len(last), "segundos": round(time.time() - t0)}
        if narrate:
            _say(f"{len(unsettled)} app(s) still moving: "
                 + ", ".join(f"{a[0]}={a[1]}/{a[2]}" for a in unsettled[:4]))
        time.sleep(poll)
    unsettled = [a for a in last if len(a) == 3 and (a[1] != "Synced" or a[2] != "Healthy")]
    return {"asentado": False, "apps": len(last), "segundos": round(time.time() - t0),
            "moviendose": [f"{a[0]}={a[1]}/{a[2]}" for a in unsettled[:8]],
            "por_que": "they did not all reach Synced+Healthy inside the wait. A wait that "
                       "ran out is a failure, never a «probably fine»"}


def chart_renders(repo, chart, version):
    """Does the candidate chart render at all, before a line is written?

    The cheapest possible way to find out that a version does not exist,
    that the repo moved, or that the chart's values changed shape — and
    it costs nothing next to discovering the same thing from a sync that
    half-applied.
    """
    if not repo or not chart or not version:
        return {"renderiza": None, "por_que": "the Application does not say repo, chart "
                                              "and version all three"}
    # Same rule as upstream.for_chart, and for the same reason: a
    # repoURL with no scheme is an OCI registry. helm accepts
    # `quay.io/jetstack/charts` and so does the Application that pins
    # cert-manager; reading it as http answers «unknown url type» about
    # a chart that renders perfectly.
    args = ["helm", "template", "candidate"]
    if repo.startswith("oci://") or "://" not in repo:
        base = repo[len("oci://"):] if repo.startswith("oci://") else repo
        args += [f"oci://{base.rstrip('/')}/{chart}"]
    else:
        args += [chart, "--repo", repo.rstrip("/")]
    args += ["--version", version]
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=180)
    except Exception as e:                                # noqa: BLE001
        return {"renderiza": None, "por_que": f"{type(e).__name__}: {e}"}
    if r.returncode != 0:
        return {"renderiza": False, "por_que": (r.stderr or r.stdout).strip()[-300:]}
    return {"renderiza": True, "documentos": r.stdout.count("\n---")}


# ══════════════════════════════════════════════════════════════════════
#  bumps: what a plan proposes, read back as something to apply
# ══════════════════════════════════════════════════════════════════════
def proposals(plan_doc, all_pins):
    """The `bump:` steps of an `aegis update plan` document, paired with
    the pin each one names. A proposal whose pin is not in the tree any
    more is dropped with its reason: the plan may be minutes old and the
    tree is what gets written."""
    out, lost = [], []
    for step in (plan_doc or {}).get("steps", []):
        name = step.get("step") or ""
        if not name.startswith("bump:") or step.get("state") != "done":
            continue
        _, cls, pin_name = name.split(":", 2)
        # `pins.read` keys its dictionary by the TUPLE (class, name);
        # `pin.key` is the string the documents carry. Confusing the two
        # is the bug that threw away a whole live measurement on
        # 2026-09-18, and it is written down here because the two
        # spellings of the same identity are going to keep meeting.
        pin = all_pins.get((cls, pin_name))
        if pin is None:
            lost.append({"pin": f"{cls}:{pin_name}",
                         "por_que": "the plan names it and the tree does not carry it any more"})
            continue
        out.append({"pin": pin, "de": pin.current, "a": step.get("ultima"),
                    "capa": step.get("capa"), "clase": cls})
    return out, lost


def host_downloads(root=None):
    """Which host tools phase 05 downloads by version, as opposed to
    handing to apt.

    A window has to know this BEFORE it writes anything. A `userland`
    pin whose tool falls to the apt branch carries a number nobody
    delivers: the window would commit the bump, run the phase, and the
    phase would refuse — correctly, and three commits too late. Read off
    the phase itself, so a tool that gains or loses its own branch moves
    this answer with it and nothing has to be remembered.
    """
    root = pathlib.Path(root) if root else paths.aegis_root()
    f = root / "init" / "phases" / "05-host.sh"
    if not f.is_file():
        return None            # not «none of them»: nobody could look
    text = f.read_text(encoding="utf-8")
    m = re.search(r"^install_binary\(\)\s*\{(.*?)^\}", text, re.M | re.S)
    if not m:
        return None
    out = set()
    for bm in re.finditer(r"^\s{8}([a-z0-9|]+)\)", m.group(1), re.M):
        out.update(bm.group(1).split("|"))
    return out


def subject(pin, old, new):
    """What a window's commit says it did. One shape, so that a human
    reading `git log` a month later sees a column and not prose."""
    return f"chore(update): {pin.cls} {pin.name} {old} → {new}"


__all__ = [n for n in dir() if not n.startswith("_")]
