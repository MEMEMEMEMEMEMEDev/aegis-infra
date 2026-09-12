"""Check 132 — the chain never draws a link it did not measure.

THE DRIFT THAT WOULD NOT FAIL. `aegis builds` reads an event the
pipeline writes, and decides whether an image was scanned by looking at
`scan_skipped`. Rename that field in Jenkinsfile.app and the reader gets
None, None is not `"true"`, and the link is drawn as DONE. An image
nobody scanned would show a green tick — the exact inversion of what the
panel exists to prove, produced by a rename nobody would think twice
about. Neither file mentions the other.

So the fields are derived from the pipeline's own event and compared.

And two more, both about not drawing what was not measured:
  · the links beyond this source (ArgoCD's sync, Kyverno's admission)
    are reported as NOT EVALUATED, by name. Omitting them would let a
    reader count four ticks and believe the deploy arrived.
  · a build the anti-loop skipped is not «done» on any link: nothing was
    built, so nothing was scanned or signed, and saying otherwise
    invents work.
"""
import importlib.machinery
import importlib.util
import os
import re
import sys

ROOT = sys.argv[1]
BUILDS = os.path.join(ROOT, "libexec", "aegis-builds")
JENKINS = os.path.join(ROOT, "seed", "platform", "docs", "protocols", "templates",
                       "Jenkinsfile.app")

if not os.path.isfile(BUILDS):
    print("SCOPE: there is no builds command")
    sys.exit(0)


def code(path):
    try:
        return "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                         if not l.lstrip().startswith("#"))
    except OSError:
        return None


src = code(BUILDS)
pipeline = code(JENKINS)

# ── 1 · the fields it reads are the ones the pipeline writes ─────────
if pipeline is None:
    print(f"SCOPE: {os.path.relpath(JENKINS, ROOT)} is not there — the coupling could not "
          f"be compared and half of this check did not run")
else:
    # What the event carries, from the printf that builds it.
    written = set(re.findall(r'"([a-z_]+)":\s*"?%s', pipeline))
    # What the reader asks of it.
    read = set(re.findall(r'event\.get\("([a-z_]+)"\)', src))
    # `_msg` and `_time` are vlogs' own, not the pipeline's.
    read -= {"_msg", "_time"}
    for field in sorted(read - written):
        print(f"aegis-builds reads the event field {field!r} and the pipeline does not write "
              f"it: the reader gets nothing, nothing is not 'true', and the link is drawn as "
              f"DONE — an image nobody scanned with a green tick on it")

# ── 2 and 3 · what it refuses to draw ────────────────────────────────
# A libexec command has no .py extension, so the loader has to be given
# explicitly: spec_from_file_location returns None otherwise, and the
# traceback that follows talks about NoneType instead of about a file
# python did not recognise.
spec = importlib.util.spec_from_loader(
    "aegis_builds_probe", importlib.machinery.SourceFileLoader("aegis_builds_probe", BUILDS))
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as e:                                    # noqa: BLE001
    print(f"libexec/aegis-builds cannot be imported ({e}): its chain could not be exercised")
    print("SCOPE: only the field coupling was compared")
    sys.exit(0)

beyond = getattr(mod, "BEYOND", None)
if not beyond:
    print("aegis-builds declares no links BEYOND what it measures: ArgoCD's sync and the "
          "cluster's admission would simply be missing, and four ticks read as a deploy "
          "that arrived")
elif "links_elsewhere" not in src:
    print("aegis-builds declares links BEYOND what it measures and does not carry them in "
          "its document: a gap nobody can read is a gap nobody sees, and four ticks read "
          "as a deploy that arrived")

chain_fn = getattr(mod, "_chain", None)
if chain_fn is None:
    print("aegis-builds has no _chain(): the shape this check exercises is gone")
else:
    skipped, _ = chain_fn({"skip_build": "true"})
    for link, state in skipped.items():
        if state == "done":
            print(f"a build the anti-loop skipped is reported as {link}=done: nothing was "
                  f"built, so nothing was scanned or signed, and a tick there invents work")
    unscanned, _ = chain_fn({"skip_build": "false", "scan_skipped": "true",
                             "sign_skipped": "true", "digest": "sha256:x"})
    for link in ("scan", "sign"):
        if unscanned.get(link) == "done":
            print(f"an image the pipeline did NOT {link} is drawn as {link}=done: the two "
                  f"links no other platform shows are exactly the two this must not invent")
    nodigest, _ = chain_fn({"skip_build": "false", "scan_skipped": "false",
                            "sign_skipped": "false"})
    if nodigest.get("digest") == "done":
        print("a build that wrote no digest is drawn as digest=done: the deploy never "
              "happened and the chain says it did")

print(f"SCOPE: {len(read) if pipeline else 0} event field(s) compared against the pipeline, "
      f"and the chain exercised on a skipped, an unscanned and a digest-less build")
