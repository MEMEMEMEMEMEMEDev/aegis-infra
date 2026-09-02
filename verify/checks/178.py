# scanner of check 178 — no path of the artifact copies a file of the
# seed into the instance without rendering it, and the advice the drift
# report prints names a path that does.
#
# It is python, in its own file, for the two reasons this repo has paid
# for: a sed that fails silently turns a check green (check 166), and a
# grep that reads the paragraph explaining the fix accuses the fix
# (checks 161, 163, 165, 166, 167, 168, 170). Here BOTH diseases are
# present at once — the function under test PRINTS a `cp` on purpose,
# and the comment above it explains why that `cp` is wrong — so the
# scan drops comments AND lines that only print before looking for
# anything that executes.
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])

# ── which files ─────────────────────────────────────────────────────
# DERIVED from the tree, never listed: a hand-written list of "the
# places that could copy" is exactly the shape that went out of date
# eight times yesterday. Everything the product executes on the host is
# scanned; three top-level trees are not, each for a reason:
#   verify/  the verifier COPIES trees on purpose (the teeth run on a
#            copy) — its copies are the instrument, not the product
#   seed/    the seed's own code runs INSIDE the instance; it has no
#            seed of its own to copy from
#   docs/    prose, and prose is not a path
SKIP_TOP = {"verify", "seed", "docs", ".git"}
SHEBANG = re.compile(r"^#!.*\b(bash|sh|python3?)\b")


def sources():
    for p in sorted(root.rglob("*")):
        if not p.is_file() or p.is_symlink():
            continue
        rel = p.relative_to(root)
        if rel.parts[0] in SKIP_TOP:
            continue
        if p.suffix in (".sh", ".py", ".bash"):
            yield p, rel
            continue
        try:
            head = p.open(encoding="utf-8", errors="replace").readline()
        except OSError:
            continue
        if SHEBANG.match(head):
            yield p, rel


# ── comments, and lines that only speak ─────────────────────────────
# `#` opens a comment at the start of a line or after whitespace, so
# ${var#pat} and an https:// inside a string survive.
HASH = re.compile(r"(^|\s)#.*$")
# A line whose first word is a printing verb SAYS something; it does
# not DO it. The whole subject of this check is a helper whose output
# contains the word `cp`, and the first version of the sibling check
# (170) read that suggestion as the helper copying.
PRINTS = re.compile(r"^\s*(log_(?:info|ok|warn|error)|echo|printf|print|die)\b")


def code_lines(text):
    """(line number, code) for every line that DOES something."""
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        if PRINTS.match(line):
            continue
        out.append((i, HASH.sub(r"\1", line)))
    return out


def printed_lines(text):
    """(line number, raw line) for every line that only PRINTS.

    Raw, and not stripped of comments: a `# then commit and push` at
    the end of the message IS part of the message.
    """
    return [(i, l) for i, l in enumerate(text.splitlines(), 1)
            if PRINTS.match(l) and not l.lstrip().startswith("#")]


# ── the two trees, named as this artifact names them ────────────────
SEED_LIT = re.compile(r"seed/platform|seed[\"'\s]*[/,][\s\"']*platform|AEGIS_ROOT[\"']?\s*/\s*[\"']?seed")
INST_LIT = re.compile(r"PLATFORM_DIR|platform_dir\s*\(|AEGIS_HOME[\"']?\s*/\s*[\"']?platform")
ASSIGN = re.compile(r"^\s*(?:local\s+|export\s+|declare\s+-\w+\s+)?([A-Za-z_]\w*)\s*=\s*(.+)$")
VARREF = re.compile(r"\$\{?([A-Za-z_]\w*)|(?<![\w.$])([A-Za-z_]\w*)(?![\w(])")


def classify_vars(lines):
    """Which local names hold a path in the seed, and which in the instance.

    Two passes so that a name built out of another one (SEED = ROOT /
    "seed" / "platform"; f = SEED / rel) is classified too.
    """
    seedish, instish = set(), set()
    for _ in range(3):
        for _n, l in lines:
            m = ASSIGN.match(l)
            if not m:
                continue
            name, val = m.group(1), m.group(2)
            if SEED_LIT.search(val) or refs(val) & seedish:
                seedish.add(name)
            if INST_LIT.search(val) or refs(val) & instish:
                instish.add(name)
    return seedish, instish


def refs(text):
    return {a or b for a, b in VARREF.findall(text)}


def is_seed(tok, seedish):
    return bool(SEED_LIT.search(tok)) or bool(refs(tok) & seedish)


def is_inst(tok, instish):
    return bool(INST_LIT.search(tok)) or bool(refs(tok) & instish)


# ── the copies ──────────────────────────────────────────────────────
# The verbs that put a file where it was not. `install` is here because
# `install -m` is a copy with a mode, and a copy with a mode
# un-renders a file exactly like a copy without one.
SH_COPY = re.compile(r"(?<![\w./-])(cp|rsync|install)\s+([^\n;|&]*)")
# and the words with which a message forbids what it names (see below).
NEGATED = re.compile(r"\b(never|not|don't|do not|instead of|rather than|no)\b", re.I)
PY_COPY = re.compile(r"shutil\.(copy|copy2|copyfile|copytree|move)\s*\(([^)]*)\)")


def copy_args(line, python):
    for m in (PY_COPY if python else SH_COPY).finditer(line):
        raw = m.group(2)
        if python:
            toks = [t.strip() for t in raw.split(",") if t.strip()]
        else:
            toks = [t for t in raw.split() if t and not t.startswith("-")]
        if len(toks) >= 2:
            yield toks[:-1], toks[-1]


# ── who encloses a line ─────────────────────────────────────────────
SH_FN = re.compile(r"^([A-Za-z_][\w-]*)\s*\(\)\s*\{")
PY_FN = re.compile(r"^(\s*)def\s+([A-Za-z_]\w*)\s*\(")


def functions(text, python):
    """name -> (first line, last line) for every function in the file."""
    fns = {}
    lines = text.splitlines()
    if python:
        for i, l in enumerate(lines):
            m = PY_FN.match(l)
            if not m:
                continue
            indent = len(m.group(1))
            end = len(lines)
            for j in range(i + 1, len(lines)):
                s = lines[j]
                if s.strip() and (len(s) - len(s.lstrip())) <= indent:
                    end = j
                    break
            fns[m.group(2)] = (i + 1, end)
    else:
        for i, l in enumerate(lines):
            m = SH_FN.match(l)
            if not m:
                continue
            end = len(lines)
            for j in range(i + 1, len(lines)):
                if lines[j] == "}":
                    end = j + 1
                    break
            fns[m.group(1)] = (i + 1, end)
    return fns


def enclosing(fns, n):
    hit = None
    for name, (a, b) in fns.items():
        if a <= n <= b and (hit is None or (b - a) < (fns[hit][1] - fns[hit][0])):
            hit = name
    return hit


RENDER = "render_platform_placeholders"
# The refusal that makes the ONE legitimate unrendered copy legitimate:
# the birth of an instance copies the whole seed and refuses outright on
# a tree that already has a history — so it never lands on a rendered
# file. Any other copy has to render.
REFUSES_ON_HISTORY = re.compile(r"PLATFORM_DIR/\.git")

findings = []
render_paths = []
sites = 0

for path, rel in sources():
    text = path.read_text(encoding="utf-8", errors="replace")
    python = path.suffix == ".py" or "python" in text.splitlines()[0][:60]
    lines = code_lines(text)
    seedish, instish = classify_vars(lines)
    fns = functions(text, python)
    for n, l in lines:
        for srcs, dst in copy_args(l, python):
            if not is_inst(dst, instish):
                continue
            if not any(is_seed(s, seedish) for s in srcs):
                continue
            sites += 1
            # The scope that has to answer for the copy: the function
            # it lives in, or the script itself when it is at the top
            # level (a phase copies from the seed and renders further
            # down — the copy is not inside anything).
            fn = enclosing(fns, n)
            a, b = fns[fn] if fn else (1, len(text.splitlines()))
            where = f"{rel}:{n}" + (f" ({fn})" if fn else "")
            scope = [(i, x) for i, x in lines if a <= i <= b]
            # AFTER, not merely present: a render that already ran when
            # the copy lands renders nothing. Order is the property.
            if any(RENDER in x for i, x in scope if i > n):
                if fn:
                    render_paths.append(fn)
            elif any(REFUSES_ON_HISTORY.search(x) for _i, x in scope):
                pass          # the birth copy: it never lands on a rendered tree
            else:
                findings.append(
                    f"{where} copies a file of the seed over the instance and afterwards neither renders it "
                    f"({RENDER}) nor refuses to write onto a tree with a history: the seed's placeholders "
                    f"land in a rendered tree — measured, __ROOT_DOMAIN__ back in Jenkins's route")

# ── the advice ──────────────────────────────────────────────────────
# The report says WHICH file differs; the operator does whatever the
# report tells them to do next. Until 2026-09-01 that was a bare `cp`,
# and the bare `cp` is the bug. The name of the path that renders is
# DERIVED from the scan above — writing "seed_fetch" here would be a
# second list to keep in step with the code.
common = root / "lib" / "common.sh"
if common.is_file():
    text = common.read_text(encoding="utf-8", errors="replace")
    fns = functions(text, False)
    if "seed_drift_report" in fns:
        a, b = fns["seed_drift_report"]
        advice = [(n, l) for n, l in printed_lines(text) if a <= n <= b]
        if not render_paths:
            findings.append(
                "no path in the artifact brings a file of the seed over WITH the render, so there is "
                "nothing for seed_drift_report to advise but the bare copy that un-renders the file")
        elif not any(any(p in l for p in render_paths) for _n, l in advice):
            findings.append(
                f"seed_drift_report tells the operator what differs and never names the path that brings "
                f"it over rendered ({', '.join(sorted(set(render_paths)))}): the advice is the half that acts")
        for n, l in advice:
            if not SH_COPY.search(l):
                continue
            # A message that spells the copy in order to FORBID it is
            # the point of the message, not the defect — and telling
            # the two apart is the only thing here that has to read
            # prose as prose. It is read narrowly: a negation, on the
            # very line that spells the copy. Anything wider would be
            # the trap this repo keeps falling into.
            if NEGATED.search(l):
                continue
            if SEED_LIT.search(l) and INST_LIT.search(l):
                findings.append(
                    f"lib/common.sh:{n} advises copying the seed's file over the instance's: that copy "
                    f"is what put __ROOT_DOMAIN__ back into Jenkins's route on 2026-09-01 — the advice "
                    f"has to name the path that renders")

for f in findings:
    print(f)
print(f"__COUNT__ {sites}", file=sys.stderr)
