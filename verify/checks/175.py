# scanner of check 175 — the verb that repoints an imported repo's FROMs
# at the installation that will build it.
#
# TWO INSTRUMENTS, and neither of them is a grep over the file:
#
#   · the rewriter is EXERCISED. `_rebase_text` and `_current_tag` are
#     pure enough to be called from here (text in, text out; the tag
#     derivation with its two sources injected), so this check asks the
#     command what it DOES instead of reading what it says. A verb made
#     inert — one that returns without rewriting — is red on the first
#     assertion, which is the whole point of having it.
#   · the shape is read with the AST. Comments are not code, and the
#     parser is what enforces that: `ast` never sees them. This file
#     documents the defect it hunts right beside the fix, in the same
#     words, and a check that reads that paragraph accuses the fix —
#     eight times in one day is what taught the house to stop.
#
# The one thing read as text is the `# aegis-subcommands:` header, which
# IS a comment by construction: it is read exactly as bin/aegis reads it
# (first 20 lines, first match), so a comment further down that quotes
# the line cannot be mistaken for the declaration.
import ast
import importlib.machinery
import importlib.util
import os
import pathlib
import re
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
app = root / "libexec" / "aegis-app"
if not app.is_file():
    print("libexec/aegis-app does not exist: this check has no subject")
    raise SystemExit(0)

src = app.read_text(encoding="utf-8", errors="replace")
tree = ast.parse(src)
bad = []

VERB = "rebase"

# ── the verb exists, and the dispatcher can see it ───────────────────
header = "\n".join(src.splitlines()[:20])
m = re.search(r"^# aegis-subcommands:[ \t]*(.*)$", header, re.M)
declared = (m.group(1).split() if m else [])
if VERB not in declared:
    bad.append(f"libexec/aegis-app does not declare `{VERB}` in its `# aegis-subcommands:` "
               f"header (it declares: {' '.join(declared) or 'nothing'}) — the menu is built "
               f"from that line and check 112 validates every invocation against it, so a "
               f"subcommand missing from it does not exist as far as the product is concerned")

functions = {n.name: n for n in ast.walk(tree)
             if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
if VERB not in functions:
    bad.append(f"libexec/aegis-app defines no `{VERB}()`: the subcommand has no body")

# The subparser and ITS dry mode. Read in line order because `s` is
# rebound for each subcommand, so what an `add_argument` belongs to is
# the `add_parser` above it and nothing else.
main = functions.get("main")
parsers, current, with_check, dispatched = [], None, set(), False
if main is not None:
    calls = sorted((n for n in ast.walk(main) if isinstance(n, ast.Call)),
                   key=lambda n: (n.lineno, n.col_offset))
    for c in calls:
        name = c.func.attr if isinstance(c.func, ast.Attribute) else getattr(c.func, "id", "")
        first = c.args[0].value if (c.args and isinstance(c.args[0], ast.Constant)) else None
        if name == "add_parser":
            current = first
            parsers.append(first)
        elif name == "add_argument" and first == "--check" and current is not None:
            with_check.add(current)
        elif name == VERB:
            dispatched = True
if VERB not in parsers:
    bad.append(f"main() registers no `{VERB}` subparser: argparse would answer «invalid "
               f"choice» and no help would ever name the verb")
elif VERB not in with_check:
    bad.append(f"the `{VERB}` subparser declares no --check: without a dry mode the only way "
               f"to find out what it would rewrite is to let it rewrite, and this command "
               f"edits repositories that are not the platform's")
if not dispatched:
    bad.append(f"main() never calls `{VERB}()`: the subcommand parses and does nothing")

# ── the call graph, derived from the AST and not listed ──────────────
# Edges are every name called under a function, nested definitions
# included: a closure defined inside a function is that function's code,
# and the resolver this command hands to the rewriter is exactly that.
edges = {name: {(c.func.attr if isinstance(c.func, ast.Attribute) else getattr(c.func, "id", ""))
                for c in ast.walk(fn) if isinstance(c, ast.Call)}
         for name, fn in functions.items()}
reach, todo = set(), [VERB]
while todo:
    fn = todo.pop()
    if fn in reach or fn not in edges:
        continue
    reach.add(fn)
    todo.extend(edges[fn])


def _consts(fn):
    """Every string constant of a function, docstrings left out."""
    node = functions[fn]
    doc = ast.get_docstring(node, clean=False)
    out = []
    for n in ast.walk(node):
        if isinstance(n, ast.Constant) and isinstance(n.value, str):
            if doc is not None and n.value == doc:
                continue
            out.append(n.value)
    return out


# ── the reference comes from `aegis image from`, and from nowhere else ──
image_from = [fn for fn in functions
              if any(isinstance(c, ast.Call)
                     and isinstance(c.func, ast.Attribute) and c.func.attr == "run"
                     and isinstance(c.func.value, ast.Name) and c.func.value.id == "cli"
                     and len(c.args) >= 2
                     and getattr(c.args[0], "value", None) == "image"
                     and getattr(c.args[1], "value", None) == "from"
                     for c in ast.walk(functions[fn]))]
if not image_from:
    bad.append("nothing in libexec/aegis-app invokes `aegis image from`: that command is the "
               "only one that knows the digest the internal registry serves AND the only one "
               "that refuses an image which is present and unsigned — resolving a FROM any "
               "other way pins something Kyverno rejects at admission")
elif len(image_from) > 1:
    bad.append(f"`aegis image from` is invoked from {len(image_from)} functions "
               f"({', '.join(sorted(image_from))}): one door, or the second one is the one "
               f"that forgets what the first measures")
elif not (set(image_from) & reach):
    bad.append(f"`{VERB}` does not reach {image_from[0]}, the only caller of `aegis image "
               f"from`: whatever digest it writes was not measured against this "
               f"installation's registry")

# A TABLE OF ITS OWN is the failure this verb exists to end: a digest
# written down anywhere but the registry that serves it is a second
# place for the truth to live, and the stale one is always the cheap one.
for fn in sorted(reach):
    for s in _consts(fn):
        if re.search(r"sha256:[0-9a-f]{16,}", s):
            bad.append(f"{fn}() carries a literal digest ({s[:60]}…): a digest is measured in "
                       f"the registry that serves it, never written into the product")
            break

# ── it writes files and it does not push ─────────────────────────────
# Only a Call's OWN arguments (and the elements of a list handed to it)
# count as an invocation. The command prints the exact push for the
# operator to run, and that sentence is an f-string — text for a person
# is not an argument to git.
for fn in sorted(reach):
    for c in (n for n in ast.walk(functions[fn]) if isinstance(n, ast.Call)):
        args = []
        for a in c.args:
            if isinstance(a, ast.Constant):
                args.append(a.value)
            elif isinstance(a, (ast.List, ast.Tuple)):
                args += [e.value for e in a.elts if isinstance(e, ast.Constant)]
        if "push" in args:
            bad.append(f"{fn}() pushes (line {c.lineno}): pinning an image and putting it in "
                       f"production are two decisions (images.md §2), and this verb takes "
                       f"only the first")

# ── EXERCISED: what the rewriter actually does ───────────────────────
os.environ["AEGIS_ROOT"] = str(root)
# the instance is pointed at the tree under test and never at the
# operator's: this check reads the product, and the only platform
# directory it looks at is the temporary one it writes below.
os.environ["AEGIS_HOME"] = str(root)
loader = importlib.machinery.SourceFileLoader("aegis_app_under_test", str(app))
spec = importlib.util.spec_from_loader("aegis_app_under_test", loader)
mod = importlib.util.module_from_spec(spec)
try:
    loader.exec_module(mod)
except ImportError as e:
    print(f"__COULDNOT__ libexec/aegis-app cannot be imported here: {e}", file=sys.stderr)
    raise SystemExit(3)

HOST = mod._internal_registry()
STALE = "a" * 64
FRESH = "f" * 64
CASES = {
    "an internal FROM pinned by another installation":
        f"FROM {HOST}/aegis-base-nginx:3.22-000001@sha256:{STALE}\n",
    "the same, with a stage alias":
        f"FROM {HOST}/golang:1.26.6-alpine@sha256:{STALE} AS build\n",
    "an internal FROM with no digest at all":
        f"FROM {HOST}/aegis-base-node\n",
}
UNTOUCHED = {
    "a public FROM, which the from-guard governs and this verb does not":
        "FROM docker.io/library/alpine:3.21\n",
    "a FROM naming an earlier stage of the same file":
        "FROM build AS final\n",
    "a COMMENT showing a FROM — the paragraph beside the defect":
        f"# FROM {HOST}/aegis-base-nginx:3.22-000001@sha256:{STALE}\n",
}


def resolve(name, tag):
    return f"{HOST}/{name}:{tag or 'derived'}@sha256:{FRESH}"


n_cases = 0
for what, text in CASES.items():
    n_cases += 1
    try:
        new, changes = mod._rebase_text(text, resolve)
    except Exception as e:                                  # noqa: BLE001
        bad.append(f"the rewriter blew up on {what}: {e!r}")
        continue
    if not changes or FRESH not in new:
        bad.append(f"{what} is NOT repointed: the verb is inert, and an imported repo stays "
                   f"pinned to a digest this installation never built — which is the "
                   f"from-guard refusing the build, by hand, four repos at a time")
    if STALE in new:
        bad.append(f"{what} keeps the digest of the other installation in the file")

for what, text in UNTOUCHED.items():
    n_cases += 1
    try:
        new, changes = mod._rebase_text(text, resolve)
    except Exception as e:                                  # noqa: BLE001
        bad.append(f"the rewriter blew up on {what}: {e!r}")
        continue
    if changes or new != text:
        bad.append(f"{what} was rewritten, and it must not be: {new.strip()!r}")

# A FROM already pinned to what this installation serves is RECOGNISED
# and left alone. The two answers have to stay apart: «there was nothing
# to repoint here» and «there is no such FROM in this file at all» are
# reported differently, and a report that collapses them tells an
# operator their repo is fine when what happened is that nothing in it
# was ever looked at.
n_cases += 1
already = f"FROM {HOST}/aegis-base-nginx:3.22-000004@sha256:{FRESH}\n"
new, changes = mod._rebase_text(already, lambda name, tag: f"{HOST}/{name}:{tag}@sha256:{FRESH}")
if new != already:
    bad.append(f"a FROM already pinned to what this installation serves was rewritten: "
               f"{new.strip()!r}")
if not changes:
    bad.append("a FROM that already names the internal registry is not even reported as "
               "seen: «nothing to repoint here» and «no such FROM in this file» become the "
               "same answer, and the second one is the one that hides an unread repo")

# ── EXERCISED: the tag is derived, and from the owner of each family ──
# The declaration owns a mirrored third party's tag; the registry owns
# the build number of a base the platform builds. Both are injected here
# so the assertion is about the RULE and not about what any live
# instance happens to hold today.
tmp = tempfile.mkdtemp(prefix="aegis-check-175.")
os.makedirs(os.path.join(tmp, "mirror-images"), exist_ok=True)
with open(os.path.join(tmp, "mirror-images", "images.txt"), "w", encoding="utf-8") as fh:
    fh.write("# a comment is not a declaration\n")
    fh.write("#example.invalid/library/golang:0.0-old@sha256:" + STALE + "\tgolang:0.0-old\n")
    fh.write("example.invalid/library/golang:1.26.6-alpine@sha256:" + STALE
             + "\tgolang:1.26.6-alpine\n")
mod.PLATFORM_DIR = tmp
mod._served_tags = lambda: {"aegis-base-nginx": ["3.22-000004", "3.21-000002", "3.22-000001"]}
TAGS = [
    ("golang", "1.26-alpine", "1.26.6-alpine",
     "a mirrored third party keeps the tag the platform DECLARES for it, not the one the "
     "repo arrived with — the mismatch phase 80 already had to solve for the canary"),
    ("aegis-base-nginx", "3.22-000001", "3.22-000004",
     "a base the platform builds carries a build number born in THIS installation's "
     "registry, so keeping the old one names a tag that does not exist here"),
    ("aegis-base-nginx", "3.21-000002", "3.21-000002",
     "the alpine minor is a version decision and is KEPT: a rebase does not move anybody "
     "from the 3.21 line to 3.22"),
]
for name, old, want, why in TAGS:
    n_cases += 1
    try:
        got = mod._current_tag(name, old)
    except Exception as e:                                  # noqa: BLE001
        bad.append(f"deriving the tag of {name} (pinned at {old}) blew up: {e!r}")
        continue
    if got != want:
        bad.append(f"{name} pinned at {old} resolves to {got!r} and this installation serves "
                   f"{want!r}: {why}")

# Both owners are consulted, and each is asked of the artifact that owns
# it: the mirror list on disk, the served tags of `aegis ci digests`.
if not any("images.txt" in s for fn in reach for s in _consts(fn)):
    bad.append("nothing in the rebase path reads mirror-images/images.txt: the tag of a "
               "mirrored third party is a declaration, and dropping that source leaves the "
               "verb pinning whatever tag the repo arrived with")
if not any(isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
           and c.func.attr == "run" and isinstance(c.func.value, ast.Name)
           and c.func.value.id == "cli" and len(c.args) >= 2
           and getattr(c.args[0], "value", None) == "ci"
           and getattr(c.args[1], "value", None) == "digests"
           for fn in reach for c in ast.walk(functions[fn])):
    bad.append("nothing in the rebase path asks `aegis ci digests` which tags this "
               "installation serves: the build number of an owned base is born in its "
               "registry and no file on this disk can know it")

for line in bad:
    print(line)
print(f"__COUNT__ {n_cases}", file=sys.stderr)
